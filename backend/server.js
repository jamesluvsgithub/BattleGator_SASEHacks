const express    = require('express');
const http       = require('http');
const { Server } = require('socket.io');
const path       = require('path');

const app    = express();
const server = http.createServer(app);
const io     = new Server(server);

const PORT = process.env.PORT || 3000;
const HARDWARE_TOKEN = process.env.HARDWARE_TOKEN;

const GRID_ROWS = 7;
const GRID_COLS = 7;

const hardwareState = {
  player1: { row: null, col: null, special: false },
  player2: { row: null, col: null, special: false }
};

function decodeOneHot(byte, limit) {
  if (!Number.isInteger(byte) || byte < 0 || byte > 127) return null;
  if (byte === 0 || (byte & (byte - 1)) !== 0) return null;

  const index = Math.log2(byte);
  return index < limit ? index : null;
}

app.use(express.static(path.join(__dirname, '../frontend')));
app.use(express.json());

const players    = {};
const shipData   = {};
const readyState = {};
let   gameActive = false;
let   turn       = 'player1';

function getId(role) {
  return Object.keys(players).find(id => players[id] === role);
}

function bothReady() {
  return readyState['player1'] === true && readyState['player2'] === true;
}

io.on('connection', (socket) => {

  const takenRoles = Object.values(players);
  if (!takenRoles.includes('player1')) {
    players[socket.id] = 'player1';
    readyState['player1'] = false;
    console.log(`Player 1 connected: ${socket.id}`);
    socket.emit('assignRole', { role: 'player1' });
    socket.emit('waitingForPlacement');
  } else if (!takenRoles.includes('player2')) {
    players[socket.id] = 'player2';
    readyState['player2'] = false;
    console.log(`Player 2 connected: ${socket.id}`);
    socket.emit('assignRole', { role: 'player2' });
    socket.emit('waitingForPlacement');
  } else {
    console.log(`Spectator connected: ${socket.id}`);
    return;
  }

  socket.on('placeShips', ({ ships }) => {
    const role = players[socket.id];
    if (!role) return;

    shipData[role] = ships;
    readyState[role] = true;
    console.log(`${role} placed ships:`, ships);

    const otherRole = role === 'player1' ? 'player2' : 'player1';
    const otherId = getId(otherRole);
    if (otherId) io.to(otherId).emit('opponentReady');

    if (bothReady()) {
      gameActive = true;
      turn = 'player1';
      console.log('Both players ready — game starting!');
      io.emit('gameStart');
      const p1Id = getId('player1');
      if (p1Id) io.to(p1Id).emit('yourTurn');
    } else {
      socket.emit('waitingForOpponent');
    }
  });

  socket.on('attack', ({ row, col }) => {
    const role = players[socket.id];
    if (!gameActive) return;
    if (role !== turn) return;

    if (!Number.isInteger(row) || row < 0 || row >= GRID_ROWS ||
        !Number.isInteger(col) || col < 0 || col >= GRID_COLS) return;

    const targetRole = role === 'player1' ? 'player2' : 'player1';
    const targetId = getId(targetRole);
    if (targetId) {
      io.to(targetId).emit('incomingAttack', { row, col });
    }
  });

  socket.on('attackResult', ({ row, col, result }) => {
    const defenderRole = players[socket.id];
    const attackerRole = defenderRole === 'player1' ? 'player2' : 'player1';
    const attackerId = getId(attackerRole);

    if (attackerId) {
      io.to(attackerId).emit('attackResult', { row, col, result });
    }

    if (result === 'hit' || result === 'sunk') {
      const keepId = getId(attackerRole);
      if (keepId) io.to(keepId).emit('yourTurn');
      console.log(`${attackerRole} hit! They go again.`);
    } else {
      turn = defenderRole;
      const nextId = getId(turn);
      if (nextId) io.to(nextId).emit('yourTurn');
      console.log(`${attackerRole} missed. ${turn}'s turn now.`);
    }
  });

  socket.on('gameOver', ({ winner }) => {
    const otherRole = winner === 'player1' ? 'player2' : 'player1';
    const otherId = getId(otherRole);
    if (otherId) io.to(otherId).emit('gameOver', { winner });
    gameActive = false;
    console.log(`Game over! ${winner} wins.`);
  });

  socket.on('disconnect', () => {
    const role = players[socket.id];
    console.log(`Disconnected: ${socket.id} (${role})`);

    if (gameActive && role) {
      const otherRole = role === 'player1' ? 'player2' : 'player1';
      const otherId = getId(otherRole);
      if (otherId) io.to(otherId).emit('opponentDisconnected');
    }

    delete players[socket.id];
    if (role) {
      delete readyState[role];
      delete shipData[role];
      hardwareState[role] = {
        row: null, col: null, special: false
      };
    }

    gameActive = false;
    turn = 'player1';
  });
});

// Receive a hardware input from Python.
app.post('/hardware-input', (req, res) => {
  if (!HARDWARE_TOKEN) {
    return res.status(503).json({
      error: 'HARDWARE_TOKEN is not configured'
    });
  }

  if (req.get('x-hardware-token') !== HARDWARE_TOKEN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { player, row_byte, col_byte, special } = req.body || {};

  if (player !== 'player1' && player !== 'player2') {
    return res.status(400).json({ error: 'Invalid player' });
  }

  const current = hardwareState[player];
  const row = decodeOneHot(row_byte, GRID_ROWS);
  const col = decodeOneHot(col_byte, GRID_COLS);

  // Remember the last valid row/column selection.
  if (row !== null) current.row = row;
  if (col !== null) current.col = col;

  // Detect the rising edge of the special button.
  const pressed = special === 1 || special === true;
  const risingEdge = pressed && !current.special;
  current.special = pressed;

  const playerId = getId(player);

  if (playerId) {
    io.to(playerId).emit('hardwareInput', {
      row: current.row,
      col: current.col,
      special: pressed
    });
  }

  // Fire only on a new press and only on this player's turn.
  const fire =
    risingEdge &&
    gameActive &&
    turn === player &&
    current.row !== null &&
    current.col !== null &&
    !!playerId;

  if (fire) {
    io.to(playerId).emit('hardwareAttack', {
      row: current.row,
      col: current.col
    });
  }

  res.json({
    ok: true,
    player,
    row: current.row,
    col: current.col,
    special: pressed,
    fired: fire
  });
});

server.listen(PORT, () => {
  console.log(`\nBattleGator server running at http://localhost:${PORT}\n`);
});

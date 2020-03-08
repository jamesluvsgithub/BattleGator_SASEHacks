import os
import subprocess
import sys
import requests

URL = os.environ.get('BATTLEGATOR_URL', '').rstrip('/') + '/hardware-input'
TOKEN = os.environ.get('HARDWARE_TOKEN', '')

"""
Transmits hardware player input from a C++ program to Vultr.

Set BATTLEGATOR_URL and HARDWARE_TOKEN in  .env.
run:
python -m pip install requests
python hardware_bridge.py ./your_cpp_program
"""


def post_input(session, player, row_byte, col_byte, special):
    response = session.post(
        URL,
        json={'player': player, 
              'row_byte': row_byte,
              'col_byte': col_byte, 
              'special': special},
        headers={'x-hardware-token': TOKEN},
        timeout=3,
    )
    response.raise_for_status()


def read_exact(stream, count):
    data = bytearray()
    while len(data) < count:
        part = stream.read(count - len(data))
        if not part:
            return None
        data.extend(part)
    return data


def main():
    with subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE) as proc, requests.Session() as session:
        while True:
            frame = read_exact(proc.stdout, 4)
            if frame is None:
                break
            p1row, p1col, p2row, p2col = frame
            for player, row, col in (('player1', p1row, p1col), ('player2', p2row, p2col)):
                post_input(session, player, row & 0x7F, col & 0x7F, (row >> 7) & 1)

if __name__ == '__main__':
    main()

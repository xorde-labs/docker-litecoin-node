#!/usr/bin/env python3
# Copyright (c) 2015-2021 The litecoin Core developers
# Copyright (c) 2022 Xorde Technologies
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

from argparse import ArgumentParser
from base64 import urlsafe_b64encode
from getpass import getpass
from os import urandom

import hmac

def generate_salt(size):
    """Create size byte hex salt"""
    return urandom(size).hex()

def generate_password():
    """Create 32 byte b64 password"""
    return urlsafe_b64encode(urandom(32)).decode('utf-8')

def password_to_hmac(salt, password):
    m = hmac.new(bytearray(salt, 'utf-8'), bytearray(password, 'utf-8'), 'SHA256')
    return m.hexdigest()

def main():
    parser = ArgumentParser(description='Encrypt password for a JSON-RPC user')
    parser.add_argument('password', help='leave empty to generate a random password or specify "-" to prompt for password')
    args = parser.parse_args()

    if not args.password:
        sys.exit()
    elif args.password == '-':
        args.password = getpass()

    # Create 16 byte hex salt
    salt = generate_salt(16)
    password_hmac = password_to_hmac(salt, args.password)

    print('{0}${1}'.format(salt, password_hmac))

if __name__ == '__main__':
    main()

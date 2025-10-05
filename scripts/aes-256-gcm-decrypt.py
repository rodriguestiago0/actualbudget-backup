import base64
import hashlib
import argparse
from os import environ
from sys import exit
from Crypto.Cipher import AES

#Color Presets
RED = '\033[31m'
RESET = '\033[0m'


#Setup argparse
parser = argparse.ArgumentParser(description='Process encryption params')
parser.add_argument('--salt', required=True, help='Base64-ecoded salt value')
parser.add_argument('--password', required=True, help='The password for key derivation')
parser.add_argument('--iv', required=True, help='Initialization Vector value')
parser.add_argument('--authtag', required=True, help='Auth Tag value')
parser.add_argument('--input', required=True, help='Path to file for decryption')
parser.add_argument('--output', required=True, help='Path to save decrypted file')
args = parser.parse_args()

#Read from argparse
password = args.password.encode('utf-8')
#Note that ActualBudget uses the base64 encoded salt as-is with no decoding
salt = args.salt.encode('utf-8')
iv_b64 = args.iv
auth_tag_b64 = args.authtag

#Check if any variables were not set properly
check_not_empty = {
    'E2E_PASS_ARG':password,
    'SALT':salt,
    'IV':iv_b64,
    'AUTH_TAG':auth_tag_b64,
}
if not all(check_not_empty.values()):
    empty = [name for name, value in check_not_empty.items() if not value]
    print(f"{RED}The following required variables are empty:{RESET}", ', '.join(empty))
    exit(1)
#Set input and output paths
encrypted_file_path = args.input
decrypted_file_path = args.output

# Decode base64 inputs as needed
iv = base64.b64decode(iv_b64)
auth_tag = base64.b64decode(auth_tag_b64)

# Derive the 256-bit AES key using PBKDF2-HMAC-SHA512
key = hashlib.pbkdf2_hmac('sha512', password, salt, 10000, dklen=32)

# Read ciphertext from file
with open(encrypted_file_path, 'rb') as f:
    ciphertext = f.read()
    f.close()

# Initialize AES-GCM cipher for decryption using key and iv
cipher = AES.new(key, AES.MODE_GCM, nonce=iv)

# Decrypt ciphertext and verify authentication tag
plaintext = cipher.decrypt_and_verify(ciphertext, auth_tag)

# Write decrypted output to <input>_decrypted.zip
with open(decrypted_file_path, 'wb') as f:
    f.write(plaintext)
    f.close()

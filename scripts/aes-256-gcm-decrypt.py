import base64
import hashlib
from os import environ
from sys import exit
from Crypto.Cipher import AES

#Color Presets
RED = '\033[31m'
RESET = '\033[0m'

#TODO: For environ.get calls check if they are empty before subscripting them
#TODO: You really should just pass these as command line args from bash as it does not require an export
#Read from environment
password = environ.get('E2E_PASS_ARG').encode('utf-8')
#Note that ActualBudget uses the base64 encoded salt as-is with no decoding
salt = environ.get('SALT').encode('utf-8')
iv_b64 = environ.get('IV')
auth_tag_b64 = environ.get('AUTH_TAG')

#Check if any variables were not set properly
check_not_empty = {
    'E2E_PASS_ARG':password,
    'SALT':salt,
    'IV':iv_b64,
    'AUTH_TAG':auth_tag_b64,
}
if not all(check_not_empty.values()):
    empty = [name for name, value in check_not_empty.items() if not value]
    print(f"{RED}The following required variables are empty:{RESET}", ', '.join(missing))
    sys.exit(1)
#Set input and output paths
encrypted_file_path = environ.get('BACKUP_FILE_ZIP_ARG')
decrypted_file_path = environ.get('BACKUP_FILE_ZIP_ARG')[:-4]+"-decrypted.zip"

# Decode base64 inputs as needed
iv = base64.b64decode(iv_b64)
auth_tag = base64.b64decode(auth_tag_b64)

# Derive the 256-bit AES key using PBKDF2-HMAC-SHA512
key = hashlib.pbkdf2_hmac('sha512', password, salt, 10000, dklen=32)

# Read ciphertext from file
with open(encrypted_file_path, 'rb') as f:
    ciphertext = f.read()

# Initialize AES-GCM cipher for decryption using key and iv
cipher = AES.new(key, AES.MODE_GCM, nonce=iv)

# Decrypt ciphertext and verify authentication tag
plaintext = cipher.decrypt_and_verify(ciphertext, auth_tag)

# Write decrypted output to <input>_decrypted.zip
#TODO above
with open(decrypted_file_path, 'wb') as f:
    f.write(plaintext)

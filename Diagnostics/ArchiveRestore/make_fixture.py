#!/usr/bin/env python3
"""Create only a fixed, wholly synthetic public-CI ZIP. Never accepts user data."""
import json
import pathlib
import sys
import zipfile

TITLE = 'Synthetic ZIP Restore Acceptance'
QUESTION = 'Synthetic ZIP acceptance question.'
ANSWER = 'Synthetic ZIP acceptance answer.'

def create(destination):
    conversation = {
        'id': '00000000-0000-0000-0000-000000000201',
        'title': TITLE, 'create_time': 100.0, 'update_time': 102.0,
        'current_node': 'reply',
        'mapping': {
            'question': {'parent': None, 'message': {
                'id': '00000000-0000-0000-0000-000000000202', 'create_time': 101.0,
                'author': {'role': 'user'}, 'status': 'finished_successfully',
                'content': {'content_type': 'multimodal_text', 'parts': [QUESTION,
                    {'content_type': 'image_asset_pointer', 'asset_pointer': 'sediment://synthetic-ui-asset'}]}}},
            'reply': {'parent': 'question', 'message': {
                'id': '00000000-0000-0000-0000-000000000203', 'create_time': 102.0,
                'author': {'role': 'assistant'}, 'status': 'finished_successfully',
                'channel': 'final', 'recipient': 'all',
                'content': {'content_type': 'text', 'parts': [ANSWER]}}}
        }
    }
    records = [('conversations.json', json.dumps([conversation], ensure_ascii=False).encode()),
               ('assets/synthetic-ui-asset.bin', b'Synthetic unsupported media; not a real image.\n'),
               ('unsupported-record.txt', b'Synthetic retained archive record.\n'),
               ('assets/reviewed-note.txt', b'Synthetic reviewed attachment.\n')]
    with zipfile.ZipFile(destination, 'x') as archive:
        for name, data in records:
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100600 << 16
            archive.writestr(info, data)
    return records

if __name__ == '__main__':
    create(pathlib.Path(sys.argv[1]))

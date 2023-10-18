import sys
import os
import json
import urllib
from urllib.request import Request, urlopen

def progressbar(it, prefix='', size=60, out=sys.stdout):
    count = len(it)

    def show(j):
        x = int(size * j / count)
        print(f"{prefix}[{u'█' * x}{('.' * (size - x))}] {j}/{count}", end='\r', file=out, flush=True)

    show(0)
    for i, item in enumerate(it):
        yield item
        show(i + 1)
    print('\n', flush=True, file=out)


def request(method, url, data=None, decode_data=True):
    if not data:
        data = {}

    result = urlopen(Request(url, method=method, data=json.dumps(data).encode(),
                                      headers={'Accept': 'application/json',
                                               'Authorization': 'Bearer ' + str(os.getenv('CROWDIN_API')),
                                               'Content-Type': 'application/json'}))
    if decode_data:
        return json.loads(result.read().decode())

def fetch(url):
    return json.loads(urlopen(Request(url, method='GET')).read().decode())

if __name__ == '__main__':
    projectId =  611911
    sourceId = 33

    current_translation = fetch('https://raw.githubusercontent.com/GameTec-live/ChameleonUltraGUI/main~1/chameleonultragui/lib/l10n/app_en.arb')
    branch_translation = json.load(open('chameleonultragui/lib/l10n/app_en.arb'))
    strings = request('GET', f'https://api.crowdin.com/api/v2/projects/{projectId}/strings?limit=500')

    for key, value in branch_translation.items():
        failed = False
        if key not in current_translation.keys():
            try:
                data = {'identifier': key, 'text': value, 'fileId': sourceId}
                string = request('POST', f'https://api.crowdin.com/api/v2/projects/{projectId}/strings', data)
                data = {'stringId': string['data']['id'], 'languageId': 'en', 'text': value}
                translation = request('POST', f'https://api.crowdin.com/api/v2/projects/{projectId}/translations', data)
                data = {'translationId': translation['data']['id']}
                translation = request('POST', f'https://api.crowdin.com/api/v2/projects/{projectId}/approvals', data)
            except urllib.error.HTTPError as e:
                failed = True
                print(e.reason)
        if failed or (key in current_translation.keys() and current_translation[key] != value):
            for string in strings['data']:
                if string['data']['identifier'] == key:
                    try:
                        data = [{'op': 'replace', 'path': '/text', 'value': value}]
                        string = request('PATCH', f'https://api.crowdin.com/api/v2/projects/{projectId}/strings/' + str(string['data']['id']), data)
                        data = {'stringId': string['data']['id'], 'languageId': 'en', 'text': value}
                        translation = request('POST', f'https://api.crowdin.com/api/v2/projects/{projectId}/translations', data)
                        data = {'translationId': translation['data']['id']}
                        translation = request('POST', f'https://api.crowdin.com/api/v2/projects/{projectId}/approvals', data)
                    except urllib.error.HTTPError as e:
                        print(e.reason)
     
    # remove old strings
    to_remove = []
    for key, value in current_translation.items():
        if key not in branch_translation.keys():
            to_remove.append(key)

    for string in strings['data']:
        if string['data']['identifier'] not in branch_translation.keys():
            to_remove.append(key)

    for remove in to_remove:
        for string in strings['data']:
            if string['data']['identifier'] == remove:
                request('DELETE', f'https://api.crowdin.com/api/v2/projects/{projectId}/strings/' + str(string['data']['id']), decode_data=False)
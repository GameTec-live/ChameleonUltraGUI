import sys
import os
import json
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


def request(method, url, data=None):
    if not data:
        data = {}
    return json.loads(urlopen(Request(url, method=method, data=json.dumps(data).encode(),
                                      headers={'Accept': 'application/json',
                                               'Authorization': 'Bearer ' + str(os.getenv('CROWDIN_API')),
                                               'Content-Type': 'application/json'})).read().decode())
def fetch(url):
    return json.loads(urlopen(Request(url, method='GET')).read().decode())

if __name__ == '__main__':
    projectId =  611911
    sourceId = 33

    current_translation = fetch('https://raw.githubusercontent.com/GameTec-live/ChameleonUltraGUI/main/chameleonultragui/lib/l10n/app_en.arb')
    branch_translation = json.load(open('chameleonultragui/lib/l10n/app_en.arb'))

    for key, value in branch_translation.items():
        if key == '@@locale':
            continue
        if key not in current_translation.keys() or current_translation[key] != value:
            data = {'identifier': key, 'text': value, 'fileId': sourceId}
            request('POST', f'https://api.crowdin.com/api/v2/projects/{projectId}/strings', data)

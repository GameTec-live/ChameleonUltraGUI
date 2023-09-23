import json
import os
import sys
import urllib.error
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
                                               'Authorization': 'Bearer ' + os.getenv('CROWDIN_API'),
                                               'Content-Type': 'application/json'})).read().decode())


for language in progressbar(
        request('GET', 'https://crowdin.com/api/v2/projects/611911/files/33/languages/progress?limit=500')['data']):
    try:
        progress = request('GET',
                           f"https://crowdin.com/api/v2/projects/611911/languages/{language['data']['languageId']}/progress")
    except urllib.error.HTTPError:
        continue
    if progress['data'][0]['data']['words']['translated'] / progress['data'][0]['data']['words']['total'] >= 0.7:
        try:
            translation = request('POST', 'https://crowdin.com/api/v2/projects/611911/translations/exports',
                                  {'targetLanguageId': language['data']['languageId'], 'format': 'arb-export',
                                   'skipUntranslatedStrings': True, 'fileIds': [33]})
        except urllib.error.HTTPError:
            continue
        export = urlopen(Request(translation['data']['url'], method='GET')).read()
        translations = json.loads(export.decode())
        locale = translations['@@locale']
        json.dump(translations, open(f'app_{locale}.arb', 'w+'), indent=2)

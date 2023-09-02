import json
import os
import sys
import urllib.error
from urllib.request import Request, urlopen


def progressbar(it, prefix="", size=60, out=sys.stdout):
    count = len(it)

    def show(j):
        x = int(size * j / count)
        print(f"{prefix}[{u'█' * x}{('.' * (size - x))}] {j}/{count}", end='\r', file=out, flush=True)

    show(0)
    for i, item in enumerate(it):
        yield item
        show(i + 1)
    print("\n", flush=True, file=out)


def request(method, url, data=None):
    if not data:
        data = {}
    return json.loads(urlopen(Request(url, method=method, data=json.dumps(data).encode(),
                                      headers={'Accept': 'application/json',
                                               'Authorization': 'Bearer ' + os.getenv('CROWDIN_API'),
                                               'Content-Type': 'application/json'})).read().decode())


for language in progressbar(request('GET', 'https://crowdin.com/api/v2/projects/610545/files/9/languages/progress?limit=500')['data']):
    try:
        progress = request('GET',
                           f'https://crowdin.com/api/v2/projects/610545/languages/{language["data"]["id"]}/progress')
    except urllib.error.HTTPError:
        continue
    if progress['data'][0]['data']['words']['translated']:
        translation = request("POST", "https://crowdin.com/api/v2/projects/610545/translations/exports",
                              {"targetLanguageId": language["data"]["id"], "format": "arb-export",
                               "skipUntranslatedStrings": True, "fileIds": [9]})
        export = urlopen(Request(translation['data']['url'], method='GET')).read()
        translations = json.loads(export.decode())
        translations['@@locale'] = language['data']['osxLocale']
        json.dump(translations, open(f"app_{language['data']['osxLocale']}.arb", "w+"), indent=2)

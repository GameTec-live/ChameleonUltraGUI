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

def add_string_to_source(string):
    projectId =  611911
    sourceId = 33

    try:
        string_parsed = string.split('+++ chameleonultragui/lib/l10n/app_en.arb ', 1)[1].replace(' ', '').replace(',', '').replace('\n','').split('+')[1:]
        for s in string_parsed:
            data = {'identifier': key.replace('"', ''), 'text': value.replace('"', ''), 'fileId': sourceId}
            try:
                key, value = s.split(':')
                request('POST', f"https://api.crowdin.com/api/v2/projects/{projectId}/strings", data)
                print("Added: ", key)
            except Exception as e:
                print(e)

    except:
        print(e)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python script.py <cadena_a_agregar>")
        sys.exit(1)

    string_to_be_added = sys.argv[1]
    add_string_to_source(string_to_be_added)

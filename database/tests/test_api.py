import urllib.request
import json

def test_api():
    try:
        # Test 1: all contests
        with urllib.request.urlopen("http://127.0.0.1:8000/contests") as res:
            data = json.loads(res.read().decode())
            print("All Contests API:", [c['title'] for c in data])

        # Test 2: filter by query
        with urllib.request.urlopen("http://127.0.0.1:8000/contests?q=Math") as res:
            data = json.loads(res.read().decode())
            print("Search 'Math' API:", [c['title'] for c in data])

        # Test 3: filter by strategy
        with urllib.request.urlopen("http://127.0.0.1:8000/contests?strategy=ICPC") as res:
            data = json.loads(res.read().decode())
            print("Strategy ICPC API:", [c['title'] for c in data])

        # Test 4: filter by timeline
        with urllib.request.urlopen("http://127.0.0.1:8000/contests?timeline=ONGOING") as res:
            data = json.loads(res.read().decode())
            print("Timeline ONGOING API:", [c['title'] for c in data])

    except Exception as e:
        print("API test failed:", e)

if __name__ == "__main__":
    test_api()

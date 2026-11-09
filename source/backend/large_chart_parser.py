import sys
import json

def parse_large_chart():
    try:
        data = json.load(sys.stdin)

        json.dump(data, sys.stdout)

        return 0
    except Exception as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(parse_large_chart())
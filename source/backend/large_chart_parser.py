import sys
import json

def parse_large_chart(file_path):
    try:
        file_size = 0
        with open(file_path, 'rb') as f:
            f.seek(0, 2)
            file_size = f.tell()
            f.seek(0)

        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            print(f"Parsed {file_size} bytes", file=sys.stderr, flush=True)

        json.dump(data, sys.stdout)

        return 0
    except Exception as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python large_chart_parser.py <file_path>", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]
    sys.exit(parse_large_chart(file_path))
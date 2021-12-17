import argparse
from mal import AnimeSearch

parser = argparse.ArgumentParser()
parser.add_argument("name")
args = parser.parse_args()

search = AnimeSearch(args.name)
for x in search.results:
    print(f"{x.mal_id},{x.title}")

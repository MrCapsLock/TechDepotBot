import std/[asyncdispatch, tables]
import FeedNim
from FeedNim/rss import RSSItem

type
  API* = object
    url*, kind*: string

proc apiCall*(site: string): Future[seq[RSSItem]] {.async.} =
  let api = {"dev.to": API(url: "https://dev.to/feed", kind: "xml")}.toTable()
  let feeds = getRSS(api[site].url)
  for item in feeds.items:
    result.add(item)

import std/[asyncdispatch, strformat]
import FeedNim
from FeedNim/rss import RSSItem

proc devtoCrawler(): Future[seq[RSSItem]] {.async.} =
  let url: string = fmt("https://dev.to/feed")
  let feeds = getRSS(url)
  for item in feeds.items:
    result.add(item)

proc mediumcomCrawler(tag: string): Future[seq[RSSItem]] {.async.} =
  let url: string = fmt("https://medium.com/feed/tag/{tag}")
  let feeds = getRSS(url)
  for item in feeds.items:
    result.add(item)

proc apiCall*(site: string): Future[seq[RSSItem]] {.async.} =
  if site == "dev.to":
    return waitFor devtoCrawler()
  elif site == "medium.com/flutter":
    return waitFor mediumcomCrawler("flutter")
  elif site == "medium.com/devops":
    return waitFor mediumcomCrawler("devops")
  elif site == "medium.com/python":
    return waitFor mediumcomCrawler("python")
  elif site == "medium.com/php":
    return waitFor mediumcomCrawler("php")
  elif site == "medium.com/golang":
    return waitFor mediumcomCrawler("golang")

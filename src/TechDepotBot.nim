import telebot
import std/[asyncdispatch, logging, options, db_sqlite, strformat]
from strutils import strip, parseInt
import apiHandler
import messageTemplates
import times, schedules

var L = newConsoleLogger(fmtStr = "$levelname, [$time] ")
addHandler(L)


let db = open("depot.db", "", "", "")

const API_KEY = slurp("secret.key")
const CHANNEL_ID = slurp("channel.id").parseInt

proc createDB(): Future[bool] {.async.} =
  db.exec(sql"""CREATE TABLE IF NOT EXISTS users (
    id      INTEGER,
    name    VARCHAR(63) NOT NULL
  )""")
  db.exec(sql"""CREATE TABLE IF NOT EXISTS posts (
    id      INTEGER NOT NULL PRIMARY KEY,
    title   VARCHAR(127),
    url     TEXT,
    author  VARCHAR(63),
    date    DATE
  )""")
  db.exec(sql"""CREATE TABLE IF NOT EXISTS categories (
    name    VARCHAR(63) NOT NULL
  )""")

proc broadcastHandler(b: Telebot, post: string): Future[bool] {.async.} =
  for user in db.fastRows(sql"SELECT * FROM users"):
    discard b.sendMessage(user[0].parseInt, post, parseMode = "markdown")

proc sendToChannelHandler(b: Telebot, post: string): Future[bool] {.async.} =
  discard b.sendMessage(CHANNEL_ID, post, parseMode = "markdown")

proc startHandler(b: Telebot, c: Command): Future[bool] {.async.} =
  discard b.sendMessage(c.message.chat.id, greetingsTemplate,
        replyToMessageId = c.message.messageId,
    parseMode = "markdown")

proc helpHandler(b: Telebot, c: Command): Future[bool] {.async.} =
  discard b.sendMessage(c.message.chat.id, helpTemplate,
        replyToMessageId = c.message.messageId,
    parseMode = "markdown")

proc registerHandler(b: Telebot, c: Command): Future[bool] {.gcsafe, async.} =
  let user = db.getRow(sql"SELECT * FROM users WHERE id = ?",
      c.message.chat.id)
  # TODO: Create logger to work instead of echo.
  # echo(fmt("registerHandler::user::{user}"))
  if user != @["", ""]:
    discard b.sendMessage(c.message.chat.id, alreadyRegisteredTemplate,
          replyToMessageId = c.message.messageId,
      parseMode = "markdown")
  else:
    db.exec(sql"INSERT INTO users (id, name) VALUES (?, ?)",
        c.message.chat.id, c.message.fromUser.get().firstName)
    discard b.sendMessage(c.message.chat.id, registerTemplate,
          replyToMessageId = c.message.messageId,
      parseMode = "markdown")

proc unregisterHandler(b: Telebot, c: Command): Future[bool] {.gcsafe, async.} =
  if db.getRow(sql"DELETE FROM users WHERE id = ?", c.message.chat.id) == @[]:
    discard b.sendMessage(c.message.chat.id, unregisterTemplate,
          replyToMessageId = c.message.messageId,
      parseMode = "markdown")

proc categoryHandler(b: Telebot, c: Command): Future[bool] {.async.} =
  echo(c.params)
# var categories = ""
# for category in db.fastRows(sql"SELECT * FROM categories"):
#   categories.add(category[0])
# discard b.sendMessage(c.message.chat.id, categories,
#         replyToMessageId = c.message.messageId,
#     parseMode = "markdown")
#     var postText = fmt("""*Title:* [{post.title}]({post.link})
# *Author:* `{post.author}`
# *Publish date:* {post.pubDate}""")
#     discard b.sendMessage(c.message.chat.id, postText, parseMode = "markdown")

proc postsHandler(b: Telebot, c: Command): Future[bool] {.async.} =
  let posts = waitFor apiCall("dev.to")
  for post in posts:
    var postText = fmt("""*Title:* [{post.title}]({post.link})
*Author:* `{post.author}`
*Publish date:* {post.pubDate}""")
    discard b.sendMessage(c.message.chat.id, postText, parseMode = "markdown")

proc initScheduler(bot: TeleBot): Future[bool] {.async.} =
  scheduler devto:
    every(seconds = 120, id = "devto", async = true):
      let posts = waitFor apiCall("dev.to")
      for post in posts:
        let postRow = db.getRow(sql"SELECT * FROM posts WHERE url = ?", post.link)
        if postRow == @["", "", "", "", ""]:
          var postText = fmt("""*Title:* [{post.title}]({post.link})
*Author:* `{post.author}`
*Publish date:* {post.pubDate}
*Source*: `dev.to`""")
          db.exec(sql"INSERT INTO posts (title, url, author, date) VALUES (?, ?, ?, ?)",
            post.title, post.link, post.author, post.pubDate)
          discard waitFor broadcastHandler(bot, postText)
          discard waitFor sendToChannelHandler(bot, postText)

  scheduler mediumcom:
    every(seconds = 120, id = "mediumcom", async = true):
      let tags = @["flutter", "devops", "python", "php", "golang"]
      for tag in tags:
        let posts = waitFor apiCall(fmt("medium.com/{tag}"))
        for post in posts:
          let postRow = db.getRow(sql"SELECT * FROM posts WHERE url = ?", post.link)
          if postRow == @["", "", "", "", ""]:
            var postText = fmt("""*Title:* [{post.title}]({post.link})
*Publish date:* {post.pubDate}
*Source*: `medium.com`
#{tag}""")
            db.exec(sql"INSERT INTO posts (title, url, author, date) VALUES (?, ?, ?, ?)",
              post.title, post.link, post.author, post.pubDate)
            discard waitFor broadcastHandler(bot, postText)
            discard waitFor sendToChannelHandler(bot, postText)

  waitFor devto.start()
  waitFor mediumcom.start()


# TODO: Fix signal catching
# proc ctrlc() {.noconv.} =
#   echo "Ctrl+C fired!"
#   db.close()


when isMainModule:
  echo("Running bot...")

  echo("Creating database...")
  discard waitFor createDB()
  echo("Database created.")

  # setControlCHook(ctrlc)

  echo("Starting bot...")
  let bot = newTeleBot(API_KEY)

  echo("Confining scheduler...")
  discard waitFor initScheduler(bot)
  echo("Scheduler configured.")

  bot.onCommand("start", startHandler)
  bot.onCommand("help", helpHandler)
  bot.onCommand("register", registerHandler)
  bot.onCommand("unregister", unregisterHandler)
  bot.onCommand("categories", categoryHandler)
  bot.onCommand("posts", postsHandler)

  bot.startWebhook("secret", "https://example.com/secret")

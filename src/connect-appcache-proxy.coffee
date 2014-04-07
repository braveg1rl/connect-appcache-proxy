async = require "async"
request = require "request"
parseURL = require("url").parse
resolveURL = require("url").resolve
{gunzip} = require "zlib"
parseManifest = require "parse-appcache-manifest"
EntityCache = require "connect-entity-cache"
zipArrays = require("underscore").zip
applyDefaults = require("underscore").defaults

defaults =
  log: (msg) ->
  overrideEntries: {}
  callback: (err) -> throw err if err
  autostart: true
  busyMessage: "The server is restarting. Try again in a minute."
  showBusy: true
  allowHeaders: ["cache-control","content-type","content-encoding","content-length","last-modified"]

module.exports = class AppcacheProxy
  constructor: (@manifestURL, @options = {}) ->
    applyDefaults @options, defaults
    @log = @options.log
    @overrideEntries = @options.overrideEntries
    @currentCache = new EntityCache log: @log
    @newCache = new EntityCache log: @log
    @ready = false
    @refreshCache options.callback if options.autostart
  
  refreshCache: (cb) ->
    @getManifest (err, manifest) =>
      return cb err if err
      @log "Downloaded manifest #{@manifestURL}"
      @log "Activating new HTML5 application cache."
      memBefore = process.memoryUsage()
      entries = parseManifest(manifest).cache
      urls = entries.map (url) => if @overrideEntries[url] then @overrideEntries[url] else url
      remoteURLs = urls.map (url) => resolveURL @manifestURL, url
      resourcePaths = entries.map (url) -> parseURL(resolveURL("/", url)).pathname
      async.map remoteURLs, fetchEntity, (err, responses) =>
        return cb err if err
        responses.map (response) =>
          for key in Object.keys(response.headers)
            delete response.headers[key] unless key in @options.allowHeaders
        resourcePairs = zipArrays resourcePaths, responses
        resourcePairs.map (pair) => @newCache.cacheEntity pair[0], pair[1].body, pair[1].headers
        @currentCache = @newCache
        @newCache = new EntityCache
        @ready = true
        @log "Activated new HTML5 application cache."
        memAfter = process.memoryUsage()
        @showMemDiff memBefore, memAfter
        cb null # successfully refreshed the cache
  
  showMemDiff: (before, after) ->
    diff = {}
    for entry in ["rss","heapTotal","heapUsed"]
      diff[entry] = Math.floor((after[entry] - before[entry]) / 1024) 
    @log "#{name} increase: #{value}KB" for name, value of diff

  getManifest: (cb) ->
    @log "Downloading manifest #{@manifestURL}"
    fetchEntity @manifestURL, (err, response) =>
      return cb err if err
      @newCache.cacheEntity "/appcache.manifest", response.body, response.headers
      return cb null, response.body.toString() unless response.headers["content-encoding"]?
      unless response.headers["content-encoding"] is "gzip"
        return next new Error "Unsupported Content-Encoding: '#{response.headers["content-encoding"]}'"
      return gunzip response.body, (err, gunzippedBody) ->
        return cb err if err
        return cb null, gunzippedBody.toString()
  
  handle: (req, res, next) =>
    if @ready then @currentCache.handle req, res, next else @handleNotReady req, res, next

  handleNotReady: (req, res, next) ->
    if @options.showBusy
      res.statusCode = 503
      res.setHeader "Content-Type", "text/plain"
      res.end @busyMessage
      @log "#{res.statusCode}: #{req.url}"
    else
      next()

fetchEntity = (url, cb) ->
  request {url: url, encoding: null}, (err, response) ->
    return cb err if err
    return cb null, response if response.statusCode is 200
    return cb new Error "Got response #{response.statusCode} for #{url}."
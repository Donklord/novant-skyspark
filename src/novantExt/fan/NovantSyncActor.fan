//
// Copyright (c) 2020, Novant LLC
// Licensed under the MIT License
//
// History:
//   11 May 2020  Andy Frank  Creation
//

using concurrent
using folio
using haystack
using util
using web

*************************************************************************
** NovantSyncActor
*************************************************************************

** NovantSyncActor manages dispatching NovantSyncWorkers.
const class NovantSyncActor
{
  new make(NovantExt ext)
  {
    this.ext  = ext
    this.pool = ActorPool { it.name="NovantSyncActorPool"; it.maxThreads=10 }
  }

  **
  ** Dispatch a new background actor to perform a trend sync for
  ** the given 'conn' and 'span' range.  If 'span' is 'null', a
  ** sync will be performed from 'Date.yesterday - novantLasySync'.
  ** If 'novantLastSync' is not defined, only 'Date.yesterday'
  ** will be synced.
  ***
  Void dispatchSync(NovantConn conn, DateSpan? span, Dict? opts)
  {
    // if span not defined, determine the range based on hisEnd;
    // if still null then this conn is already synced thru today
    // and we can short-circuit
    if (span == null) span = defSpan(conn.hisEnd)
    if (span == null) return

    if (opts == null) opts = Etc.emptyDict

    worker := NovantSyncWorker(conn, span, opts, ext.log)
    actor  := Actor(pool) |m| { worker.sync; return null }
    actor.send("run")
  }

  ** Get default span based on given 'hisEnd' date, or return 'null'
  ** if the span is already up-to-date.
  internal static DateSpan? defSpan(Date? hisEnd)
  {
    // short-circuit if already up-to-date
    yesterday := Date.yesterday
    if (hisEnd >= yesterday) return null

    // find range
    start := hisEnd==null ? yesterday : hisEnd+1day
    return DateSpan(start, yesterday)
  }

  private const NovantExt ext
  private const ActorPool pool
}

*************************************************************************
** NovantSyncWorker
*************************************************************************

** NovantSyncActor peforms the trend sync work.
const class NovantSyncWorker
{
  ** Constructor.
  new make(NovantConn conn, DateSpan span, Dict opts, Log log)
  {
    this.connUnsafe = Unsafe(conn)
    this.span = span
    this.log  = log

    // opts
    this.force = opts.has("force")
  }

  ** Perform REST API call and updateHisOk/Err work.
  Void sync()
  {
    // TODO:
    //   - support for passing in time_zone?
    //   - support for non-Number types?

    try
    {
      // short-circuit if disabled
      conn := this.conn
      if (conn.isDisabled) return

      // get sync span
      hisSpan := conn.hisStart != null && conn.hisEnd != null
        ? DateSpan(conn.hisStart, conn.hisEnd)
        : null

      // sync each date
      span.eachDay |date|
      {
        ts1 := Duration.now

        // never sync past yesterday
        if (date > Date.yesterday) return

        // if we are trying to sync yesterday, we need to wait
        // until 2:00am local time to ensure device data is
        // fully synced up to cloud
        if (date == Date.yesterday && DateTime.now.hour < 2) return

        // skip if already synced unless force=true
        if (!force && hisSpan != null && hisSpan.contains(date))
        {
          log.info("already synced ${date}")
          return
        }

        // get comma-sep point id list
        pointIds := StrBuf()
        conn.points.each |p|
        {
          id := p.rec["novantHis"]
          if (id != null) pointIds.join(id, ",")
        }

        // short-ciruit if no points
        if (pointIds.isEmpty) return

        // request data
        c := WebClient(`https://api.novant.io/v1/trends`)
        c.reqHeaders["Authorization"] = "Basic " + "${conn.apiKey}:".toBuf.toBase64
        c.reqHeaders["Accept-Encoding"] = "gzip"
        c.postForm([
          "device_id": conn.deviceId,
          "date":      date.toStr,
          "point_ids": pointIds.toStr,
          "interval":  conn.hisInterval,
        ])

        // validate
        if (c.resCode == 401) throw IOErr("Unauthorized")
        if (c.resCode != 200) throw IOErr("Invalid response code: ${c.resCode}")

        // parse and cache response
        Map map   := JsonInStream(c.resStr.in).readJson
        List data := map["data"]

        // iterate by point to add his
        numPoints := 0
        conn.points.each |point|
        {
          try
          {
            // short-circuit if not a historized point
            id := point.rec["novantHis"]?.toStr
            if (id == null) return

            items := HisItem[,]
            start := date.midnight(point.tz)
            end   := (date+1day).midnight(point.tz)
            clip  := Span.makeAbs(start, end)
            data.each |Map entry|
            {
              ts  := DateTime.fromIso(entry["ts"]).toTimeZone(point.tz)
              val := entry["${id}"] as Float
              if (val != null)
              {
                pval := NovantUtil.toConnPointVal(point, val)
                items.add(HisItem(ts, pval))
              }
            }
            point.updateHisOk(items, clip)
            numPoints++
          }
          catch (Err err) { point.updateHisErr(err) }
        }

        // update hisStart/End
        if (conn.hisStart == null || date < conn.hisStart) commit("novantHisStart", date)
        if (conn.hisEnd   == null || conn.hisEnd < date)   commit("novantHisEnd", date)

        // log metrics
        ts2 := Duration.now
        dur := (ts2 - ts1).toMillis
        log.info("syncHis successful for '${conn.dis}' @ ${date}" +
                 " [${numPoints} points, ${dur.toLocale}ms]")
      }
    }
    catch (Err err) { log.err("syncHis failed for '${conn.dis}'", err) }
  }

  ** Update conn tag.
  private Void commit(Str tag, Obj val)
  {
    // pull rec to make sure we have the most of up-to-date
    rec := conn.ext.proj.readById(conn.rec.id)
    conn.ext.proj.commit(Diff(rec, [tag:val]))
  }

  private NovantConn conn() { connUnsafe.val }
  private const Unsafe connUnsafe
  private const DateSpan span
  private const Log log

  // options
  private const Bool force := false
}

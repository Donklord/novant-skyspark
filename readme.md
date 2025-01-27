# Novant Connector for SkySpark

The NovantExt implements [SkySpark](https://skyfoundry.com) connector support
for the [Novant](https://novant.io) Smart Building PaaS.

## Installing

[rel]: https://github.com/novant-io/novant-skyspark/releases

The simplest way to install the `novantExt` is using the Install Manager tool
in SkySpark. You may also manually download the pod from [Releases][rel] and
copy into the `lib/fan/` folder. A restart is required for the extension to
take effect.

## API Keys

Access to Novant devices are built around API keys. It's recommended you
create a specific API key just for SkySpark access.

## Connectors

Each connector in SkySpark maps 1:1 to a Novant device.  To create and map a
new connector:

    novantConn
    dis: "My Device"
    apiKey: "***********"
    novantDeviceId: dv_xxxxxxxxxxxxx
    novantSyncFreq: "daily"
    novantHisInterval: "15min"

Where `apiKey` is the key you generated from the Novant platform, and
'novantDeviceId' is the Novant device id for the device to connect. See
**Syncing** section for details on `novantSyncFreq` and `novantHisInterval`.

## Cur/Write/His

Current values are configured using the `novantCur` tag on a point. Writable
points use the `novantWrite` tag.  Likewise histories use the `novantHis` tag.
The value of these tags maps to the point ID for the Novant device, which will
be in the format of `"p{id}"`.

    point
    dis: "My Point"
    novantCur: "p15"
    novantWrite: "p15"
    novantHis: "p15"
    equipRef: @equip-id
    siteRef: @site-id
    kind: "Number"
    unit: "kW"

The SkySpark write level will be carried over directly into the downstream
I/O device under the Novant gateway.  For protocols that support priority, like
Bacnet, this means the Bacnet priority array level matches the SkySpark write
level. For protocols that do not support priority (such as Modbus) this value
is ignored.

## Learn

The Novant connector supports learning.  Once a connector has been added, you
can use the Site Builder to walk the device tree and add any or all points.

## Syncing

The Novant extension is designed to automate history syncs to simplify keeping
data up-to-date.  Syncing is managed on the *connector* instead of *per-point*.
The default is to sync trend data for all points under a connector daily. A new
connector will begin syncing history `yesterday`.  If you wish to sync previous
data that is available, see the **Conn Tool** section below.

In cases where this is not desirable, you can disable auto-sync by setting the
`novantSyncFreq` on a connector to `"none"`.  You can manually sync these
connectors using the **Conn Tool**.

The Novant platform trends all data at `1min` intervals; however the default
interval we pull data into SkySpark is `15min`.  To configure SkySpark to
sync data at a more granular level, use the `novantHisInterval` tag, were the
values can be `"1min"`, `"5min"`, or `"15min"`.  Note these are `Str` values
not Numbers.

## Conn Tool

The Novant Conn Tool provides a single view to manage your device connectors.
This view will list all the current connectors in a table with easy to scan
diagnostic information.

### Sync History

The Sync History action will initiate a manual history sync for a given date
range. This can be used to sync previous data before the connector was created
in SkySpark.

### Clear History

To remove all history for all points under a connector, use the Clear History
action.  This only effects history in SkySpark.  The data from the Novant
platform can be resynced.
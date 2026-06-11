# Travels GPX Extension v1

Status: normative, human-readable interoperability contract for Travels GPX 1.1 import/export.

This document defines the canonical Travels GPX extension schema used by Travels exports and accepted by Travels imports.

## Namespace

- Namespace URI: `https://github.com/dkrnet/travels-ios/gpx/extensions/1`
- Preferred prefix: `travels`

The prefix is conventional only. Importers should identify Travels elements by namespace URI and local name where possible, not by prefix alone.

## Relationship to GPX 1.1

Travels exports GPX 1.1 and uses standard GPX fields whenever the semantics match.

Standard mappings:

- `LocationEvent.latitude` -> `trkpt/@lat`
- `LocationEvent.longitude` -> `trkpt/@lon`
- `LocationEvent.altitude` -> `trkpt/ele`
- `LocationEvent.timestamp` -> `trkpt/time`
- `LocationEvent.note` -> `trkpt/cmt`
- `Geolocation.name` -> `trkpt/name`
- Readable place summary -> `trkpt/desc`
- `LocationEvent.source` -> `trkpt/src`, when useful

Core Location accuracy values are not GPX `hdop`, `vdop`, or `pdop`.

## Internal ID exclusion rule

Travels internal database IDs MUST NOT be exported.

The following fields are internal implementation details and must not appear in GPX:

- `LocationEvent.id`
- `LocationEvent.geolocationID`
- `Geolocation.id`

## Versioning policy

- Additive optional fields may be added to extension v1.
- Changing the meaning, unit, requiredness, or XML structure of an existing v1 field requires a new namespace version.
- A future incompatible version should use a new namespace URI, for example `https://github.com/dkrnet/travels-ios/gpx/extensions/2`.
- Importers should ignore unknown optional Travels extension elements.
- Exporters should emit one Travels extension namespace version per file unless a future migration explicitly requires otherwise.

## Canonical XML structure

Preferred trackpoint structure:

```xml
<trkpt lat="..." lon="...">
  <ele>...</ele>
  <time>...</time>
  <name>...</name>
  <cmt>...</cmt>
  <desc>...</desc>
  <src>...</src>
  <extensions>
    <travels:horizontalAccuracyMeters>...</travels:horizontalAccuracyMeters>
    <travels:verticalAccuracyMeters>...</travels:verticalAccuracyMeters>
    <travels:headingDegrees>...</travels:headingDegrees>
    <travels:speedMetersPerSecond>...</travels:speedMetersPerSecond>
    <travels:timeZone>...</travels:timeZone>
    <travels:localizedDateKey>...</travels:localizedDateKey>
    <travels:source>...</travels:source>
    <travels:tags>
      <travels:tag>...</travels:tag>
    </travels:tags>
    <travels:externalReference>...</travels:externalReference>
    <travels:photoFilename>...</travels:photoFilename>
    <travels:demoData>true</travels:demoData>
    <travels:solar>
      <travels:period>...</travels:period>
      <travels:periodPercent>...</travels:periodPercent>
      <travels:calculatedAt>...</travels:calculatedAt>
    </travels:solar>
    <travels:place>
      <travels:identifier>...</travels:identifier>
      <travels:latitude>...</travels:latitude>
      <travels:longitude>...</travels:longitude>
      <travels:radiusMeters>...</travels:radiusMeters>
      <travels:horizontalAccuracyMeters>...</travels:horizontalAccuracyMeters>
      <travels:verticalAccuracyMeters>...</travels:verticalAccuracyMeters>
      <travels:altitudeMeters>...</travels:altitudeMeters>
      <travels:timestamp>...</travels:timestamp>
      <travels:bounds>
        <travels:minLatitude>...</travels:minLatitude>
        <travels:maxLatitude>...</travels:maxLatitude>
        <travels:minLongitude>...</travels:minLongitude>
        <travels:maxLongitude>...</travels:maxLongitude>
      </travels:bounds>
      <travels:name>...</travels:name>
      <travels:subThoroughfare>...</travels:subThoroughfare>
      <travels:thoroughfare>...</travels:thoroughfare>
      <travels:subLocality>...</travels:subLocality>
      <travels:locality>...</travels:locality>
      <travels:subAdministrativeArea>...</travels:subAdministrativeArea>
      <travels:administrativeArea>...</travels:administrativeArea>
      <travels:postalCode>...</travels:postalCode>
      <travels:isoCountryCode>...</travels:isoCountryCode>
      <travels:country>...</travels:country>
      <travels:inlandWater>...</travels:inlandWater>
      <travels:ocean>...</travels:ocean>
      <travels:areasOfInterest>
        <travels:areaOfInterest>...</travels:areaOfInterest>
      </travels:areasOfInterest>
    </travels:place>
  </extensions>
</trkpt>
```

Optional elements are omitted when the corresponding value is not present.

## Field table

### Event extension fields

| Element | Source field | Type | Units / format | Required? | Export rule | Import rule | Legacy aliases |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `travels:horizontalAccuracyMeters` | `LocationEvent.horizontalAccuracy` | decimal | meters | No | Export when non-negative | Parse if present | `horizontalAccuracy` |
| `travels:verticalAccuracyMeters` | `LocationEvent.verticalAccuracy` | decimal | meters | No | Export when non-negative | Parse if present | `verticalAccuracy` |
| `travels:headingDegrees` | `LocationEvent.course` | decimal | degrees clockwise from true north | No | Export when non-negative | Parse if present | `heading`, `course` |
| `travels:speedMetersPerSecond` | `LocationEvent.speed` | decimal | meters per second | No | Export when non-negative | Parse if present | `speed` |
| `travels:timeZone` | `Geolocation.timeZoneIdentifier` | string | IANA time-zone identifier | No | Export when available | Parse if present | `timeZoneIdentifier` |
| `travels:localizedDateKey` | `LocationEvent.localizedDate` | string | app date key | No | Export when available | Parse if present | `localizedDate` |
| `travels:source` | `LocationEvent.source` | string | display label | No | Export when useful | Parse if present | `src` |
| `travels:tags` | `LocationEvent.tags` | wrapper | contains repeated `travels:tag` children | No | Export when tags exist | Parse wrapper and children | `tags` |
| `travels:tag` | `LocationEvent.tags` | string | tag text | No | Export one child per logical tag token when structured tags are available; otherwise one child may contain the flat tag string | Parse repeated children and preserve order | `tags` |
| `travels:externalReference` | `LocationEvent.externalReference` | string | app-specific identifier | No | Export when available | Parse if present | none |
| `travels:photoFilename` | `LocationEvent.photoFilename` | string | filename | No | Export when available | Parse if present | none |
| `travels:demoData` | `LocationEvent.isDemo` | boolean string | `true` or `false` | No | Export `true` when demo data flag is set | Parse boolean string if present | `isDemo` |
| `travels:solar` | solar substructure | wrapper | contains Travels solar fields | No | Export when any solar value exists | Parse wrapper if present | `solarPeriod`, `solarPeriodPercent`, `solarPeriodCalculatedAt` |
| `travels:period` | `LocationEvent.solarPeriod` | string | one of the documented solar-period enum values | No | Export when solar data exists | Parse if present | `solarPeriod`, `twilightPhase` |
| `travels:periodPercent` | `LocationEvent.solarPeriodPercent` | decimal | `0.0...1.0` | No | Export when available | Parse if present | `solarPeriodPercent`, `twilightPercent` |
| `travels:calculatedAt` | `LocationEvent.solarPeriodCalculatedAt` | timestamp | UTC ISO 8601 | No | Export when available | Parse if present | `solarPeriodCalculatedAt`, `twilightCalculatedAt` |

### Place fields

| Element | Source field | Type | Units / format | Required? | Export rule | Import rule | Legacy aliases |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `travels:place` | `Geolocation` | wrapper | place metadata | No | Export when a geolocation exists | Parse wrapper if present | none |
| `travels:identifier` | `Geolocation.identifier` | string | stable place identifier | No | Export when available | Parse if present | none |
| `travels:latitude` | `Geolocation.latitude` | decimal | degrees | No | Export when available | Parse if present | none |
| `travels:longitude` | `Geolocation.longitude` | decimal | degrees | No | Export when available | Parse if present | none |
| `travels:radiusMeters` | `Geolocation.radius` | decimal | meters | No | Export when available | Parse if present | `radius` |
| `travels:horizontalAccuracyMeters` | `Geolocation.horizontalAccuracy` | decimal | meters | No | Export when non-negative | Parse if present | `horizontalAccuracy` |
| `travels:verticalAccuracyMeters` | `Geolocation.verticalAccuracy` | decimal | meters | No | Export when non-negative | Parse if present | `verticalAccuracy` |
| `travels:altitudeMeters` | `Geolocation.altitude` | decimal | meters | No | Export when available | Parse if present | `altitude` |
| `travels:timestamp` | `Geolocation.timestamp` | timestamp | UTC ISO 8601 | No | Export when available | Parse if present | none |
| `travels:bounds` | `Geolocation.minLatitude` / `maxLatitude` / `minLongitude` / `maxLongitude` | wrapper | contains numeric bounds | No | Export when any bound is available | Parse wrapper if present | `minLatitude`, `maxLatitude`, `minLongitude`, `maxLongitude` |
| `travels:minLatitude` | `Geolocation.minLatitude` | decimal | degrees | No | Export when available | Parse if present | `minLatitude` |
| `travels:maxLatitude` | `Geolocation.maxLatitude` | decimal | degrees | No | Export when available | Parse if present | `maxLatitude` |
| `travels:minLongitude` | `Geolocation.minLongitude` | decimal | degrees | No | Export when available | Parse if present | `minLongitude` |
| `travels:maxLongitude` | `Geolocation.maxLongitude` | decimal | degrees | No | Export when available | Parse if present | `maxLongitude` |
| `travels:name` | `Geolocation.name` | string | place name | No | Export when available | Parse if present | `name` |
| `travels:subThoroughfare` | `Geolocation.subThoroughfare` | string | address component | No | Export when available | Parse if present | `subThoroughfare` |
| `travels:thoroughfare` | `Geolocation.thoroughfare` | string | address component | No | Export when available | Parse if present | `thoroughfare` |
| `travels:subLocality` | `Geolocation.subLocality` | string | address component | No | Export when available | Parse if present | `subLocality` |
| `travels:locality` | `Geolocation.locality` | string | address component | No | Export when available | Parse if present | `locality` |
| `travels:subAdministrativeArea` | `Geolocation.subAdministrativeArea` | string | address component | No | Export when available | Parse if present | `subAdministrativeArea` |
| `travels:administrativeArea` | `Geolocation.administrativeArea` | string | address component | No | Export when available | Parse if present | `administrativeArea` |
| `travels:postalCode` | `Geolocation.postalCode` | string | postal code | No | Export when available | Parse if present | `postalCode` |
| `travels:isoCountryCode` | `Geolocation.isoCountryCode` | string | ISO country code | No | Export when available | Parse if present | `isoCountryCode` |
| `travels:country` | `Geolocation.country` | string | country name | No | Export when available | Parse if present | `country` |
| `travels:inlandWater` | `Geolocation.inlandWater` | string | water body name | No | Export when available | Parse if present | `inlandWater` |
| `travels:ocean` | `Geolocation.ocean` | string | ocean name | No | Export when available | Parse if present | `ocean` |
| `travels:areasOfInterest` | `Geolocation.areasOfInterest` | wrapper | contains repeated `travels:areaOfInterest` children | No | Export repeated children in stable order | Parse repeated children | `areasOfInterest` |
| `travels:areaOfInterest` | `Geolocation.areasOfInterest` | string | area name | No | Export one child per normalized area | Parse repeated children and legacy joined values | `areaOfInterest` |

## Legacy compatibility

Legacy direct child elements are import aliases only. New exports should prefer GPX standard elements plus the namespaced Travels extension.

The importer accepts the legacy direct child elements currently used by older Travels exports:

- `heading`
- `speed`
- `horizontalAccuracy`
- `timeZone`
- `timeZoneIdentifier`
- `localizedDate`
- `localizedDateKey`
- `name`
- `subThoroughfare`
- `thoroughfare`
- `subLocality`
- `locality`
- `subAdministrativeArea`
- `administrativeArea`
- `postalCode`
- `isoCountryCode`
- `country`
- `inlandWater`
- `ocean`
- `areasOfInterest`
- `note`
- `tags`
- `externalReference`
- `photoFilename`
- `isDemo`
- `solarPeriod`
- `solarPeriodPercent`
- `solarPeriodCalculatedAt`
- `twilightPhase`
- `twilightPercent`
- `twilightCalculatedAt`

The legacy `areasOfInterest` joined string remains accepted on import, but v1 export must use repeated `travels:areaOfInterest` elements.

## Import precedence

When both namespaced Travels v1 elements and legacy direct child elements provide the same value, the namespaced Travels v1 value wins.

Malformed or incomplete trackpoints without usable latitude, longitude, or timestamp are skipped.

Unknown extension elements are ignored.

Import must not require the `travels` prefix if the namespace URI and local name can be identified.

## Privacy and sensitivity

GPX exports may contain sensitive personal location history, notes, photo references, reverse-geocoded place names, and time-zone context. Follow the privacy and local-storage requirements documented in `requirements.md`.

## Examples

### Minimal valid Travels GPX v1 trackpoint

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Travels - life tracking" xmlns="http://www.topografix.com/GPX/1/1" xmlns:travels="https://github.com/dkrnet/travels-ios/gpx/extensions/1">
  <trk>
    <trkseg>
      <trkpt lat="37.3317" lon="-122.0301">
        <time>2026-05-31T12:00:00Z</time>
        <extensions>
          <travels:source>Imported</travels:source>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
```

### Full Travels GPX v1 example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Travels - life tracking" xmlns="http://www.topografix.com/GPX/1/1" xmlns:travels="https://github.com/dkrnet/travels-ios/gpx/extensions/1">
  <metadata>
    <name>Travels GPX v1 Example</name>
    <time>2026-06-01T00:00:00Z</time>
    <bounds minlat="37.3317" maxlat="37.3317" minlon="-122.0301" maxlon="-122.0301"/>
  </metadata>
  <trk>
    <name>Travels GPX v1 Example</name>
    <trkseg>
      <trkpt lat="37.3317" lon="-122.0301">
        <ele>12</ele>
        <time>2026-05-31T12:00:00Z</time>
        <name>Tom &amp; Jerry Park</name>
        <cmt>Note with &lt;angle&gt; brackets &amp; ampersands</cmt>
        <desc>Apple Park, Cupertino, California, United States</desc>
        <src>Imported</src>
        <extensions>
          <travels:horizontalAccuracyMeters>12</travels:horizontalAccuracyMeters>
          <travels:verticalAccuracyMeters>8</travels:verticalAccuracyMeters>
          <travels:headingDegrees>90</travels:headingDegrees>
          <travels:speedMetersPerSecond>1.2</travels:speedMetersPerSecond>
          <travels:timeZone>America/Los_Angeles</travels:timeZone>
          <travels:localizedDateKey>2026-05-31</travels:localizedDateKey>
          <travels:source>Imported</travels:source>
          <travels:tags>
            <travels:tag>Museum &amp; art</travels:tag>
            <travels:tag>Food &lt;travel&gt;</travels:tag>
          </travels:tags>
          <travels:externalReference>sample-reference</travels:externalReference>
          <travels:photoFilename>sample-photo.jpg</travels:photoFilename>
          <travels:demoData>true</travels:demoData>
          <travels:solar>
            <travels:period>day</travels:period>
            <travels:periodPercent>0.5</travels:periodPercent>
            <travels:calculatedAt>2026-05-31T12:05:00Z</travels:calculatedAt>
          </travels:solar>
          <travels:place>
            <travels:identifier>place-1</travels:identifier>
            <travels:latitude>37.3317</travels:latitude>
            <travels:longitude>-122.0301</travels:longitude>
            <travels:radiusMeters>25</travels:radiusMeters>
            <travels:horizontalAccuracyMeters>12</travels:horizontalAccuracyMeters>
            <travels:verticalAccuracyMeters>8</travels:verticalAccuracyMeters>
            <travels:altitudeMeters>12</travels:altitudeMeters>
            <travels:timestamp>2026-05-31T11:59:00Z</travels:timestamp>
            <travels:bounds>
              <travels:minLatitude>37.3310</travels:minLatitude>
              <travels:maxLatitude>37.3320</travels:maxLatitude>
              <travels:minLongitude>-122.0310</travels:minLongitude>
              <travels:maxLongitude>-122.0290</travels:maxLongitude>
            </travels:bounds>
            <travels:name>Tom &amp; Jerry Park</travels:name>
            <travels:subThoroughfare>1</travels:subThoroughfare>
            <travels:thoroughfare>Infinite Loop</travels:thoroughfare>
            <travels:subLocality>Cupertino West</travels:subLocality>
            <travels:locality>Cupertino</travels:locality>
            <travels:subAdministrativeArea>Santa Clara County</travels:subAdministrativeArea>
            <travels:administrativeArea>California</travels:administrativeArea>
            <travels:postalCode>95014</travels:postalCode>
            <travels:isoCountryCode>US</travels:isoCountryCode>
            <travels:country>United States</travels:country>
            <travels:inlandWater>San Francisco Bay</travels:inlandWater>
            <travels:ocean>Pacific Ocean</travels:ocean>
            <travels:areasOfInterest>
              <travels:areaOfInterest>Apple Park</travels:areaOfInterest>
              <travels:areaOfInterest>Visitor Center</travels:areaOfInterest>
            </travels:areasOfInterest>
          </travels:place>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
```

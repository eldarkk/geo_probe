package com.clockster.geo_probe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * SKELETON — receiver for GeofencingClient transition events.
 *
 * Implementation checklist (from the engineering spec, §5.2 / §6.1):
 *  - Register geofences with GeofencingClient and a MUTABLE PendingIntent
 *    (FLAG_MUTABLE): with FLAG_IMMUTABLE on Android 12+ events are silently
 *    never delivered — the prime suspect for the Gen 1 total failure.
 *  - Requires ACCESS_BACKGROUND_LOCATION (Android 10+) for background delivery.
 *  - Use GeofencingEvent.fromIntent(intent) and log the event's OWN timestamp
 *    (triggeringLocation.time), never the receipt time (§4.2).
 *  - Write events to a local JSONL/SQLite store exactly like the iOS side
 *    (Application Support/geo_probe/native_events.jsonl equivalent),
 *    then let the Dart layer drain and deduplicate by uuid.
 *  - Handlers must be idempotent — duplicate EXIT events are documented.
 *  - Any network call from here must be wrapped in a foreground promotion or
 *    WorkManager job; direct HTTP from a frozen process silently fails.
 *
 * Manifest registration (add when implementing):
 *   <receiver android:name=".GeofenceBroadcastReceiver" android:exported="false" />
 */
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // TODO(android): parse GeofencingEvent, persist enter/exit event locally.
    }
}

package com.clockster.geo_probe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * SKELETON — re-registers geofences after device reboot.
 *
 * Android does NOT restore geofences after a reboot. Without this receiver
 * geofencing works until the first reboot and then dies permanently — one of
 * the documented Gen 1 failure candidates.
 *
 * Implementation checklist:
 *  - Read the persisted region list (same store MainActivity syncs to).
 *  - Re-register all active regions with GeofencingClient.
 *  - Log a "reboot" event (with the boot reason) to the local event store so
 *    the reconciliation layer can attach a reason code to any gap.
 *
 * Manifest registration (add when implementing):
 *   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
 *   <receiver android:name=".BootReceiver" android:exported="false">
 *     <intent-filter>
 *       <action android:name="android.intent.action.BOOT_COMPLETED" />
 *     </intent-filter>
 *   </receiver>
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        // TODO(android): re-register geofences from the persisted region list.
    }
}

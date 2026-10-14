package com.barsopus.attune

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * The share sheet's "Add to plans" (Together Phase 8b). The share sheet
 * starts its target inside the sharing app's task, which would put a second
 * Attune (a second Flutter engine) there. This invisible step hands the share
 * to Attune's own task instead — onNewIntent if it's running, a fresh start if
 * not — and closes. MainActivity keeps singleTop, so the launcher icon still
 * returns to whatever was open (a payment, the cropper, a sign-in tab).
 */
class ShareTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val forward = Intent(this, MainActivity::class.java)
            .setAction(intent.action)
            .setType(intent.type)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        intent.extras?.let { forward.putExtras(it) }
        startActivity(forward)
        finish()
    }
}

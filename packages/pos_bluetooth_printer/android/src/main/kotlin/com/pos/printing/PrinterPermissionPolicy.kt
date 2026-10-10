package com.pos.printing

internal object PrinterPermissionPolicy {
    fun status(api: Int, granted: Boolean, requested: Boolean, rationale: Boolean): String =
        when {
            api < 31 || granted -> "granted"
            requested && !rationale -> "permanently_denied"
            else -> "denied"
        }
}

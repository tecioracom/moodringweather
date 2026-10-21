package com.teciora.moodringweather.wallpaper

import android.content.SharedPreferences

/** テスト用の SharedPreferences (メモリ上の Map)。apply / commit で反映する。 */
internal class FakeSharedPreferences : SharedPreferences {
    val values = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()

    override fun getString(key: String, defValue: String?): String? =
        values[key] as? String ?: defValue

    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? {
        @Suppress("UNCHECKED_CAST")
        return values[key] as? MutableSet<String> ?: defValues
    }

    override fun getInt(key: String, defValue: Int): Int = values[key] as? Int ?: defValue

    override fun getLong(key: String, defValue: Long): Long = values[key] as? Long ?: defValue

    override fun getFloat(key: String, defValue: Float): Float = values[key] as? Float ?: defValue

    override fun getBoolean(key: String, defValue: Boolean): Boolean =
        values[key] as? Boolean ?: defValue

    override fun contains(key: String): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = FakeEditor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) = Unit

    private inner class FakeEditor : SharedPreferences.Editor {
        private val changes = mutableListOf<(MutableMap<String, Any?>) -> Unit>()

        private fun change(block: (MutableMap<String, Any?>) -> Unit): SharedPreferences.Editor {
            changes += block
            return this
        }

        private fun put(key: String, value: Any?) = change { map ->
            if (value == null) {
                map.remove(key)
            } else {
                map[key] = value
            }
        }

        override fun putString(key: String, value: String?) = put(key, value)

        override fun putStringSet(key: String, values: MutableSet<String>?) = put(key, values)

        override fun putInt(key: String, value: Int) = put(key, value)

        override fun putLong(key: String, value: Long) = put(key, value)

        override fun putFloat(key: String, value: Float) = put(key, value)

        override fun putBoolean(key: String, value: Boolean) = put(key, value)

        override fun remove(key: String) = change { it.remove(key) }

        override fun clear() = change { it.clear() }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            changes.forEach { it(values) }
            changes.clear()
        }
    }
}

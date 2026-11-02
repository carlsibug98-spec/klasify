package com.klasify.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.roundToInt

private data class ScheduledWidgetClass(
    val subject: String,
    val room: String,
    val professor: String,
    val day: Int,
    val startMinutes: Int,
    val endMinutes: Int,
    // yyyy-MM-dd dates on which this occurrence is finished / not attending /
    // cancelled (sent by the app for the next 8 days).
    val markedDates: Set<String> = emptySet(),
)

private data class NextWidgetClass(
    val item: ScheduledWidgetClass,
    // 0 = today, 1 = tomorrow, 7 = same weekday next week.
    val dayDifference: Int,
    // Milliseconds to the class start (next up) or end (live now).
    val millisToBoundary: Long,
)

private data class CalendarCell(
    val label: String,
    val isToday: Boolean,
    val isWeekend: Boolean,
)

class NextClassWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val classes = readSchedule(context)
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId, classes)
        }
        scheduleNextBoundary(context, classes)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(
            context,
            appWidgetManager,
            appWidgetId,
            newOptions,
        )
        updateWidget(context, appWidgetManager, appWidgetId, readSchedule(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIME_TICK,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            BOUNDARY_ACTION,
            -> updateAllWidgets(context)
        }
    }

    companion object {
        const val PREFERENCES_NAME = "klasify_next_class_widget"
        const val SCHEDULE_KEY = "saved_schedule_json"

        // Fires just after the next class starts or ends so the "In class" state
        // and the countdowns change on time instead of waiting for the 30-minute
        // periodic refresh.
        private const val BOUNDARY_ACTION = "com.klasify.app.NEXT_CLASS_BOUNDARY"
        private const val BOUNDARY_REQUEST_CODE = 4217

        // Board layout is width-first; height decides how much of it fits.
        // Below 120dp the widget falls back to the compact status line. The
        // full 4x3 board needs ~315dp for the LATER TODAY rows; the month
        // calendar is only kept for tall 4x5-style layouts.
        private const val COMPACT_MAX_HEIGHT_DP = 120
        private const val SHELF_MIN_HEIGHT_DP = 190
        private const val LATER_MIN_HEIGHT_DP = 315
        private const val CALENDAR_MIN_HEIGHT_DP = 480

        // Launchers that never report OPTION_APPWIDGET_MIN_HEIGHT fall back to
        // the widget's default 2-cell height instead of its tallest layout.
        private const val DEFAULT_HEIGHT_DP = 100

        // Compile-time cell ids, generated alongside the layout XML
        // (scripts/make_v52_widget_layout.py emits WidgetCalendarIds.kt).
        private val CAL_CELL_IDS: IntArray = WidgetCalendarIds.CELL_IDS

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NextClassWidgetProvider::class.java)
            val widgetIds = manager.getAppWidgetIds(component)
            if (widgetIds.isNotEmpty()) {
                NextClassWidgetProvider().onUpdate(context, manager, widgetIds)
            }
        }

        private fun readSchedule(context: Context): List<ScheduledWidgetClass> {
            val preferences = context.getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            val scheduleJson = preferences.getString(SCHEDULE_KEY, "[]") ?: "[]"
            return try {
                val array = JSONArray(scheduleJson)
                buildList {
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: continue
                        val day = item.optInt("day", 0)
                        val start = item.optInt("start_minutes", -1)
                        val end = item.optInt("end_minutes", -1)
                        val subject = item.optString("subject").trim()
                        if (
                            day !in 1..7 ||
                            start < 0 ||
                            start >= 1440 ||
                            end < 1 ||
                            end > 1440 ||
                            end <= start ||
                            subject.isEmpty()
                        ) {
                            continue
                        }
                        val marked = buildSet {
                            val dates = item.optJSONArray("marked_dates")
                            if (dates != null) {
                                for (d in 0 until dates.length()) {
                                    val value = dates.optString(d, "")
                                    if (value.isNotEmpty()) add(value)
                                }
                            }
                        }
                        add(
                            ScheduledWidgetClass(
                                subject = subject,
                                room = item.optString("room").trim(),
                                professor = item.optString("professor").trim(),
                                day = day,
                                startMinutes = start,
                                endMinutes = end,
                                markedDates = marked,
                            ),
                        )
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun scheduleNextBoundary(context: Context, classes: List<ScheduledWidgetClass>) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            val intent = Intent(context, NextClassWidgetProvider::class.java)
                .setAction(BOUNDARY_ACTION)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                BOUNDARY_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.cancel(pendingIntent)
            if (classes.isEmpty()) return
            val now = Calendar.getInstance()
            val triggerAt = listOfNotNull(
                nextBoundaryMillis(classes, now),
                nextMinuteUpdateMillis(now),
            ).minOrNull() ?: return
            // Inexact on purpose: no exact-alarm permission needed, and a few
            // minutes of drift is acceptable for a minute-granularity countdown.
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }

        private fun nextMinuteUpdateMillis(now: Calendar): Long {
            val millisIntoMinute =
                now.get(Calendar.SECOND) * 1_000L + now.get(Calendar.MILLISECOND)
            // Refresh just after the minute changes so the displayed rounded
            // countdown stays in sync with the in-app hero.
            return now.timeInMillis - millisIntoMinute + 60_000L + 1_000L
        }

        private fun nextBoundaryMillis(
            classes: List<ScheduledWidgetClass>,
            now: Calendar,
        ): Long? {
            if (classes.isEmpty()) return null
            val today = dayOfWeekIndex(now)
            val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            // Int.MAX_VALUE stands for "no boundary found yet", so no nullable
            // value needs unwrapping below.
            var soonestMinutes = Int.MAX_VALUE
            for (item in classes) {
                for (boundary in listOf(item.startMinutes, item.endMinutes)) {
                    val dayDifference = (item.day - today + 7) % 7
                    var minutesUntil = dayDifference * 1440 + boundary - nowMinutes
                    if (minutesUntil <= 0) minutesUntil += 7 * 1440
                    if (minutesUntil < soonestMinutes) {
                        soonestMinutes = minutesUntil
                    }
                }
            }
            val minutesUntilMidnight = 1440 - nowMinutes
            if (minutesUntilMidnight > 0 && minutesUntilMidnight < soonestMinutes) {
                soonestMinutes = minutesUntilMidnight
            }
            if (soonestMinutes == Int.MAX_VALUE) return null
            val secondsIntoMinute =
                now.get(Calendar.SECOND) * 1000L + now.get(Calendar.MILLISECOND)
            // One second past the boundary so the widget reads the new state.
            return now.timeInMillis - secondsIntoMinute +
                soonestMinutes * 60_000L + 1_000L
        }

        /** yyyy-MM-dd for [calendar], matching the app's date keys. */
        private fun dateKey(calendar: Calendar): String {
            return String.format(
                Locale.US,
                "%04d-%02d-%02d",
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH) + 1,
                calendar.get(Calendar.DAY_OF_MONTH),
            )
        }

        /** Occurrence of [item] at [dayDifference] days from [now] is marked? */
        private fun isMarked(
            item: ScheduledWidgetClass,
            dayDifference: Int,
            now: Calendar,
        ): Boolean {
            if (item.markedDates.isEmpty()) return false
            val date = (now.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, dayDifference)
            }
            return dateKey(date) in item.markedDates
        }

        private fun findNextClass(
            classes: List<ScheduledWidgetClass>,
            now: Calendar,
        ): NextWidgetClass? {
            if (classes.isEmpty()) return null

            val today = dayOfWeekIndex(now)
            val nowMinutes =
                now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val millisIntoMinute =
                now.get(Calendar.SECOND) * 1000L + now.get(Calendar.MILLISECOND)

            val live = classes
                .filter { item ->
                    item.day == today &&
                        item.startMinutes <= nowMinutes &&
                        nowMinutes < item.endMinutes &&
                        !isMarked(item, 0, now)
                }
                .minByOrNull { it.startMinutes }
            if (live != null) {
                return NextWidgetClass(
                    item = live,
                    dayDifference = 0,
                    millisToBoundary = (live.endMinutes - nowMinutes) * 60_000L -
                        millisIntoMinute,
                )
            }

            var best: NextWidgetClass? = null
            for (item in classes) {
                var dayDifference = (item.day - today + 7) % 7
                var minutesUntil =
                    dayDifference * 1440 + item.startMinutes - nowMinutes
                if (minutesUntil <= 0) {
                    dayDifference += 7
                    minutesUntil += 7 * 1440
                }
                if (isMarked(item, dayDifference, now)) continue
                val candidate = NextWidgetClass(
                    item = item,
                    dayDifference = dayDifference,
                    millisToBoundary = minutesUntil * 60_000L - millisIntoMinute,
                )
                if (best == null || candidate.millisToBoundary < best.millisToBoundary) {
                    best = candidate
                }
            }
            return best
        }

        /** 42 cells (Sunday-first) for the month of [now]; null = blank slot. */
        private fun calendarCells(now: Calendar): List<CalendarCell?> {
            val first = (now.clone() as Calendar).apply {
                set(Calendar.DAY_OF_MONTH, 1)
            }
            val leadingBlanks = first.get(Calendar.DAY_OF_WEEK) - Calendar.SUNDAY
            val daysInMonth = now.getActualMaximum(Calendar.DAY_OF_MONTH)
            val today = now.get(Calendar.DAY_OF_MONTH)
            return List(42) { index ->
                val day = index - leadingBlanks + 1
                if (day < 1 || day > daysInMonth) {
                    null
                } else {
                    val column = index % 7
                    CalendarCell(
                        label = day.toString(),
                        isToday = day == today,
                        isWeekend = column == 0 || column == 6,
                    )
                }
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            classes: List<ScheduledWidgetClass>,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_next_class)
            val now = Calendar.getInstance()
            val today = dayOfWeekIndex(now)
            val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val todayKey = dateKey(now)

            val options = manager.getAppWidgetOptions(appWidgetId)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val heightKnown = heightDp > 0
            // HiOS reports 0 for some freshly placed widgets. Treating that as
            // "unknown, show everything" renders the tallest composition and
            // clips the bottom of a 4x3 card, so assume the default 3-cell
            // height until the launcher sends real options.
            val effectiveHeightDp = if (heightKnown) heightDp else DEFAULT_HEIGHT_DP
            val compact = effectiveHeightDp < COMPACT_MAX_HEIGHT_DP
            val showLater = heightKnown && effectiveHeightDp >= LATER_MIN_HEIGHT_DP
            val showShelf = effectiveHeightDp >= SHELF_MIN_HEIGHT_DP
            val showCalendar = heightKnown && effectiveHeightDp >= CALENDAR_MIN_HEIGHT_DP

            val todayClasses = classes.filter {
                it.day == today && todayKey !in it.markedDates
            }
            val live = todayClasses
                .filter { it.startMinutes <= nowMinutes && nowMinutes < it.endMinutes }
                .minByOrNull { it.startMinutes }
            val upcomingToday = todayClasses
                .filter { it.startMinutes > nowMinutes }
                .sortedBy { it.startMinutes }
                .map { item ->
                    NextWidgetClass(
                        item = item,
                        dayDifference = 0,
                        millisToBoundary = millisUntil(now, item.startMinutes),
                    )
                }
            val allDoneToday = todayClasses.isNotEmpty() &&
                todayClasses.all { it.endMinutes <= nowMinutes }
            val freeDay = todayClasses.isEmpty()
            val next = findNextClass(classes, now)

            when {
                classes.isEmpty() -> showEmpty(views)

                live != null && !compact -> {
                    showInClass(
                        context,
                        views,
                        live,
                        now,
                    )
                }

                live != null -> {
                    showCompact(
                        context,
                        views,
                        templateRes = R.string.next_class_widget_compact_in_class,
                        millis = millisUntil(now, live.endMinutes),
                        item = live,
                    )
                }

                upcomingToday.isNotEmpty() && !compact -> {
                    showUpcoming(
                        context,
                        views,
                        now,
                        nextClass = upcomingToday.first(),
                        remaining = upcomingToday.drop(1),
                        showLater = showLater,
                        showCalendar = showCalendar,
                    )
                }

                upcomingToday.isNotEmpty() -> {
                    showCompact(
                        context,
                        views,
                        templateRes = R.string.next_class_widget_compact_next,
                        millis = upcomingToday.first().millisToBoundary,
                        item = upcomingToday.first().item,
                    )
                }

                next != null && (allDoneToday || freeDay) -> {
                    showAllDone(
                        context,
                        views,
                        now,
                        next = next,
                        allDone = allDoneToday,
                        showShelf = showShelf,
                    )
                }

                next != null && !compact -> {
                    // Marked-out day: everything today is skipped but the next
                    // occurrence is still ahead. Render the next-up state with
                    // no LATER TODAY rows because the class is on another day.
                    showUpcoming(
                        context,
                        views,
                        now,
                        nextClass = next,
                        remaining = emptyList(),
                        showLater = false,
                        showCalendar = showCalendar,
                    )
                }

                next != null -> {
                    showCompact(
                        context,
                        views,
                        templateRes = R.string.next_class_widget_compact_next,
                        millis = next.millisToBoundary,
                        item = next.item,
                    )
                }

                allDoneToday || freeDay -> {
                    showAllDone(
                        context,
                        views,
                        now,
                        next = null,
                        allDone = allDoneToday,
                        showShelf = false,
                    )
                }

                else -> showEmpty(views)
            }

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            manager.updateAppWidget(appWidgetId, views)
        }

        // -- State renderers -------------------------------------------------

        private fun showEmpty(views: RemoteViews) {
            views.showOnly(R.id.widget_empty_container)
        }

        private fun showUpcoming(
            context: Context,
            views: RemoteViews,
            now: Calendar,
            nextClass: NextWidgetClass,
            remaining: List<NextWidgetClass>,
            showLater: Boolean,
            showCalendar: Boolean,
        ) {
            views.showOnly(R.id.container_upcoming)
            val item = nextClass.item

            bindRoomCta(
                views,
                cta = R.id.widget_upcoming_cta,
                room = R.id.widget_upcoming_cta_room,
                roomText = item.room,
            )
            bindCountdown(
                context,
                views,
                millis = nextClass.millisToBoundary,
                value1 = R.id.widget_upcoming_value_1,
                unit1 = R.id.widget_upcoming_unit_1,
                value2 = R.id.widget_upcoming_value_2,
                unit2 = R.id.widget_upcoming_unit_2,
            )
            views.setTextViewText(R.id.widget_upcoming_subject, item.subject)

            // The day chip marks today; a class on another day gets the
            // filled day pill instead (TOMORROW, or the weekday name).
            if (nextClass.dayDifference == 0) {
                views.setViewVisibility(R.id.widget_upcoming_day_chip, View.VISIBLE)
                views.setViewVisibility(R.id.widget_upcoming_day_pill, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_upcoming_day_chip, View.GONE)
                views.setViewVisibility(R.id.widget_upcoming_day_pill, View.VISIBLE)
                val dayPill = if (nextClass.dayDifference == 1) {
                    context.getString(R.string.next_class_widget_day_tomorrow)
                } else {
                    weekdayName(item.day).uppercase(Locale.getDefault())
                }
                views.setTextViewText(R.id.widget_upcoming_day_pill, dayPill)
            }

            // LATER TODAY belongs to the current day only. Its caption rides
            // the hero segment; the rows are the quiet segments below it, so
            // the hero rounds first (10/2) with rows and solo (10) without.
            val later = if (showLater) remaining.take(2) else emptyList()
            views.setViewVisibility(
                R.id.widget_upcoming_later_label,
                if (later.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setInt(
                R.id.widget_upcoming_hero,
                "setBackgroundResource",
                if (later.isEmpty()) {
                    R.drawable.next_class_widget_seg_hero_solo
                } else {
                    R.drawable.next_class_widget_seg_hero_first
                },
            )
            bindLaterRow(
                views,
                index = 1,
                item = later.getOrNull(0),
                showRow = later.isNotEmpty(),
            )
            bindLaterRow(
                views,
                index = 2,
                item = later.getOrNull(1),
                showRow = later.size > 1,
            )
            // Corner logic by position: row 1 rounds last (2/10) when it is
            // the only row, straight (2/2) when row 2 follows it.
            views.setInt(
                R.id.widget_later_row_1,
                "setBackgroundResource",
                if (later.size > 1) {
                    R.drawable.next_class_widget_seg_quiet_mid
                } else {
                    R.drawable.next_class_widget_seg_quiet_last
                },
            )
            views.setInt(
                R.id.widget_later_row_2,
                "setBackgroundResource",
                R.drawable.next_class_widget_seg_quiet_last,
            )

            views.setViewVisibility(
                R.id.widget_cal_panel,
                if (showCalendar) View.VISIBLE else View.GONE,
            )
            if (showCalendar) {
                val monthLabel = SimpleDateFormat("MMMM", Locale.getDefault())
                views.setTextViewText(R.id.widget_month_label, monthLabel.format(now.time))
                bindCalendar(context, views, now)
            }
        }

        private fun showInClass(
            context: Context,
            views: RemoteViews,
            item: ScheduledWidgetClass,
            now: Calendar,
        ) {
            views.showOnly(R.id.container_inclass)

            bindRoomCta(
                views,
                cta = R.id.widget_inclass_cta,
                room = R.id.widget_inclass_cta_room,
                roomText = item.room,
            )

            // The time range sits under the subject; the big countdown below
            // reads "24 min" — the ENDS IN caption carries the direction, so
            // no unit says "left" anymore.
            views.setTextViewText(
                R.id.widget_inclass_time,
                formatTimeRange(item.startMinutes, item.endMinutes),
            )
            bindCountdown(
                context,
                views,
                millis = millisUntil(now, item.endMinutes),
                value1 = R.id.widget_inclass_value_1,
                unit1 = R.id.widget_inclass_unit_1,
                value2 = R.id.widget_inclass_value_2,
                unit2 = R.id.widget_inclass_unit_2,
            )
            views.setTextViewText(R.id.widget_inclass_subject, item.subject)

            // The 6px elapsed bar moves at real-time speed between updates.
            val span = (item.endMinutes - item.startMinutes).coerceAtLeast(1)
            val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val elapsed = (nowMinutes - item.startMinutes).coerceIn(0, span)
            views.setProgressBar(
                R.id.widget_inclass_bar,
                100,
                elapsed * 100 / span,
                false,
            )
        }

        private fun showAllDone(
            context: Context,
            views: RemoteViews,
            now: Calendar,
            next: NextWidgetClass?,
            allDone: Boolean,
            showShelf: Boolean,
        ) {
            views.showOnly(R.id.container_alldone)

            val isWeekend = dayOfWeekIndex(now) >= 6
            val title = when {
                allDone -> context.getString(R.string.next_class_widget_all_done_title)
                isWeekend -> context.getString(R.string.next_class_widget_weekend_title)
                else -> context.getString(R.string.next_class_widget_free_day_title)
            }
            val subtitle = when {
                allDone -> context.getString(
                    R.string.next_class_widget_enjoy_rest,
                    weekdayName(dayOfWeekIndex(now)),
                )
                isWeekend -> context.getString(R.string.next_class_widget_weekend_message)
                else -> context.getString(R.string.next_class_widget_free_day_message)
            }
            views.setTextViewText(R.id.widget_alldone_title, title)
            views.setTextViewText(R.id.widget_alldone_subtitle, subtitle)

            // Two-segment stack when a next class exists: check row first
            // (10/2), seam of wallpaper, shelf last (2/10). Solo otherwise.
            val hasShelf = showShelf && next != null
            views.setInt(
                R.id.widget_alldone_top,
                "setBackgroundResource",
                if (hasShelf) {
                    R.drawable.next_class_widget_seg_quiet_first
                } else {
                    R.drawable.next_class_widget_seg_quiet_solo
                },
            )
            views.setViewVisibility(
                R.id.widget_alldone_seam,
                if (hasShelf) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_alldone_card,
                if (hasShelf) View.VISIBLE else View.GONE,
            )
            if (hasShelf && next != null) {
                val item = next.item
                val dayPill = if (next.dayDifference == 1) {
                    context.getString(R.string.next_class_widget_day_tomorrow)
                } else {
                    weekdayName(item.day).uppercase(Locale.getDefault())
                }
                views.setTextViewText(R.id.widget_alldone_day_pill, dayPill)
                views.setTextViewText(
                    R.id.widget_alldone_starts,
                    context.getString(
                        R.string.next_class_widget_starts_in,
                        formatShortCountdown(next.millisToBoundary),
                    ),
                )
                views.setTextViewText(R.id.widget_alldone_subject, item.subject)
                views.setTextViewText(
                    R.id.widget_alldone_time,
                    formatTimeRange(item.startMinutes, item.endMinutes),
                )
            }
        }

        private fun showCompact(
            context: Context,
            views: RemoteViews,
            templateRes: Int,
            millis: Long,
            item: ScheduledWidgetClass,
        ) {
            views.showOnly(R.id.container_active)
            views.setTextViewText(
                R.id.widget_label,
                context.getString(
                    templateRes,
                    formatShortCountdown(millis),
                ),
            )
            views.setTextViewText(R.id.widget_subject, item.subject)
            // The dot carries the same meaning as the caps header: orange
            // for live, inverted for next up.
            val dotColor = ContextCompat.getColor(
                context,
                if (templateRes == R.string.next_class_widget_compact_in_class) {
                    R.color.next_class_widget_live
                } else {
                    R.color.next_class_widget_accent
                },
            )
            views.setInt(R.id.widget_active_dot, "setColorFilter", dotColor)
        }

        // -- View helpers ----------------------------------------------------

        private fun RemoteViews.showOnly(containerId: Int) {
            setViewVisibility(R.id.container_upcoming, View.GONE)
            setViewVisibility(R.id.container_inclass, View.GONE)
            setViewVisibility(R.id.container_alldone, View.GONE)
            setViewVisibility(R.id.container_active, View.GONE)
            setViewVisibility(R.id.widget_empty_container, View.GONE)
            setViewVisibility(containerId, View.VISIBLE)
        }

        private fun bindRoomCta(
            views: RemoteViews,
            cta: Int,
            room: Int,
            roomText: String,
        ) {
            val trimmed = roomText.trim()
            views.setViewVisibility(cta, if (trimmed.isEmpty()) View.GONE else View.VISIBLE)
            views.setTextViewText(room, trimmed)
        }

        private fun bindCountdown(
            context: Context,
            views: RemoteViews,
            millis: Long,
            value1: Int,
            unit1: Int,
            value2: Int,
            unit2: Int,
        ) {
            val parts = countdownParts(millis)
            views.setTextViewText(value1, parts[0].first)
            views.setTextViewText(unit1, context.getString(parts[0].second))
            val hasSecond = parts.size > 1
            views.setViewVisibility(value2, if (hasSecond) View.VISIBLE else View.GONE)
            views.setViewVisibility(unit2, if (hasSecond) View.VISIBLE else View.GONE)
            if (hasSecond) {
                views.setTextViewText(value2, parts[1].first)
                views.setTextViewText(unit2, context.getString(parts[1].second))
            }
        }

        private fun bindLaterRow(
            views: RemoteViews,
            index: Int,
            item: NextWidgetClass?,
            showRow: Boolean,
        ) {
            val row = if (index == 1) R.id.widget_later_row_1 else R.id.widget_later_row_2
            val time = if (index == 1) R.id.widget_later_time_1 else R.id.widget_later_time_2
            val subject =
                if (index == 1) R.id.widget_later_subject_1 else R.id.widget_later_subject_2
            val room = if (index == 1) R.id.widget_later_room_1 else R.id.widget_later_room_2
            val roomBox =
                if (index == 1) R.id.widget_later_room_box_1 else R.id.widget_later_room_box_2

            views.setViewVisibility(row, if (showRow) View.VISIBLE else View.GONE)
            if (!showRow || item == null) return

            views.setTextViewText(time, formatMinutes12(item.item.startMinutes))
            views.setTextViewText(subject, item.item.subject)
            val roomText = formatRoom(item.item.room)
            views.setViewVisibility(roomBox, if (roomText.isEmpty()) View.GONE else View.VISIBLE)
            views.setTextViewText(room, roomText)
        }

        private fun bindCalendar(context: Context, views: RemoteViews, now: Calendar) {
            val weekdayColor = ContextCompat.getColor(
                context, R.color.next_class_widget_cal_weekday,
            )
            val weekendColor = ContextCompat.getColor(
                context, R.color.next_class_widget_cal_weekend,
            )
            val todayColor = ContextCompat.getColor(
                context, R.color.next_class_widget_day_pill_text,
            )
            val cells = calendarCells(now)
            for (index in 0 until 42) {
                val id = CAL_CELL_IDS[index]
                val cell = cells[index]
                if (cell == null) {
                    views.setViewVisibility(id, View.GONE)
                    continue
                }
                views.setViewVisibility(id, View.VISIBLE)
                views.setTextViewText(id, cell.label)
                views.setTextColor(id, when {
                    cell.isToday -> todayColor
                    cell.isWeekend -> weekendColor
                    else -> weekdayColor
                })
                views.setInt(
                    id,
                    "setBackgroundResource",
                    if (cell.isToday) R.drawable.next_class_widget_today_chip else 0,
                )
            }
        }

        private fun dayOfWeekIndex(now: Calendar): Int = when (now.get(Calendar.DAY_OF_WEEK)) {
            Calendar.SUNDAY -> 7
            else -> now.get(Calendar.DAY_OF_WEEK) - 1
        }

        private fun weekdayName(day: Int): String = when (day) {
            1 -> "Monday"
            2 -> "Tuesday"
            3 -> "Wednesday"
            4 -> "Thursday"
            5 -> "Friday"
            6 -> "Saturday"
            7 -> "Sunday"
            else -> ""
        }

        /** "242-B" -> "Class 242-B"; "Lab 2" stays "Lab 2". */
        private fun formatRoom(room: String): String =
            if (room.isBlank()) ""
            else if (Regex("[A-Za-z]{3,}").containsMatchIn(room)) room
            else "Class " + room

        /** Milliseconds from [now] to [targetMinutes] on the current day. */
        private fun millisUntil(now: Calendar, targetMinutes: Int): Long {
            val nowMinutes =
                now.get(Calendar.HOUR_OF_DAY) * 60L + now.get(Calendar.MINUTE)
            val secondsIntoMinute =
                now.get(Calendar.SECOND) * 1000L + now.get(Calendar.MILLISECOND)
            return (targetMinutes * 60_000L - nowMinutes * 60_000L - secondsIntoMinute)
                .coerceAtLeast(0L)
        }

        /** 12-hour clock: 10:00 AM, 1:30 PM, and 12:00 AM at midnight/1440. */
        private fun formatMinutes12(minutes: Int): String {
            val normalized = minutes.coerceIn(0, 1440)
            val hour24 = if (normalized == 1440) 24 else normalized / 60
            val period = if (hour24 in 12..23) "PM" else "AM"
            val hour12 = if (hour24 % 12 == 0) 12 else hour24 % 12
            val minute = (normalized % 60).toString().padStart(2, '0')
            return "$hour12:$minute $period"
        }

        /** "10:00 – 11:30 AM": en dash, one period when both ends share it. */
        private fun formatTimeRange(startMinutes: Int, endMinutes: Int): String {
            val start = formatMinutes12(startMinutes)
            val end = formatMinutes12(endMinutes)
            val startPeriod = start.takeLast(2)
            val endPeriod = end.takeLast(2)
            return if (startPeriod == endPeriod) {
                "${start.dropLast(3)} – $end"
            } else {
                "$start – $end"
            }
        }

        /**
         * Big hero countdown: the two largest units, e.g. "1 h 25 min",
         * "2 d 3 h" or "25 min". Returns (value, unit string resource) pairs.
         */
        private fun countdownParts(millis: Long): List<Pair<String, Int>> {
            val totalMinutes = (((millis.coerceAtLeast(0L) + 59_999L) / 60_000L)
                .toInt()).coerceAtMost(7 * 24 * 60)
            if (totalMinutes >= 1440) {
                val days = totalMinutes / 1440
                val hours = (totalMinutes % 1440) / 60
                return buildList {
                    add(days.toString() to R.string.next_class_widget_unit_days)
                    if (hours > 0) {
                        add(hours.toString() to R.string.next_class_widget_unit_hours)
                    }
                }
            }
            if (totalMinutes >= 60) {
                val hours = totalMinutes / 60
                val minutes = totalMinutes % 60
                return buildList {
                    add(hours.toString() to R.string.next_class_widget_unit_hours)
                    if (minutes > 0) {
                        add(minutes.toString() to R.string.next_class_widget_unit_minutes)
                    }
                }
            }
            return listOf(
                totalMinutes.coerceAtLeast(1).toString() to
                    R.string.next_class_widget_unit_minutes,
            )
        }

        /**
         * Short countdown used by the shelf and compact states: "16h 30m",
         * "1h", "24m", "2d 3h". Matches the board copy.
         */
        private fun formatShortCountdown(millis: Long): String {
            val totalMinutes = (((millis.coerceAtLeast(0L) + 59_999L) / 60_000L)
                .toInt()).coerceAtLeast(1)
            if (totalMinutes < 60) return "${totalMinutes}m"

            val days = totalMinutes / 1440
            val hours = (totalMinutes % 1440) / 60
            val minutes = totalMinutes % 60
            if (days == 0) {
                return if (minutes == 0) "${hours}h" else "${hours}h ${minutes}m"
            }
            return when {
                hours > 0 && minutes > 0 -> "${days}d ${hours}h ${minutes}m"
                hours > 0 -> "${days}d ${hours}h"
                minutes > 0 -> "${days}d ${minutes}m"
                else -> "${days}d"
            }
        }
    }
}

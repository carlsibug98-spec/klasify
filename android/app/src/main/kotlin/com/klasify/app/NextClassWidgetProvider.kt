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
    val isHappeningNow: Boolean,
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

        // Fires just after the next class starts or ends so the "In class" chip
        // and the countdowns change on time instead of waiting for the 30-minute
        // periodic refresh.
        private const val BOUNDARY_ACTION = "com.klasify.app.NEXT_CLASS_BOUNDARY"
        private const val BOUNDARY_REQUEST_CODE = 4217

        // Height tiers for the redesigned layout: the calendar needs ~190dp,
        // the today cards need ~240dp. Very short widgets (below 120dp) fall
        // back to the compact legacy line so the subject always stays readable.
        private const val COMPACT_MAX_HEIGHT_DP = 120
        private const val CALENDAR_MIN_HEIGHT_DP = 190
        private const val CARDS_MIN_HEIGHT_DP = 240
        private const val NEXT_CARD_MIN_HEIGHT_DP = 150

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
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC, triggerAt, pendingIntent)
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
            val today = when (now.get(Calendar.DAY_OF_WEEK)) {
                Calendar.SUNDAY -> 7
                else -> now.get(Calendar.DAY_OF_WEEK) - 1
            }
            val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            var soonestMinutes: Int? = null
            for (item in classes) {
                for (boundary in listOf(item.startMinutes, item.endMinutes)) {
                    val dayDifference = (item.day - today + 7) % 7
                    var minutesUntil = dayDifference * 1440 + boundary - nowMinutes
                    if (minutesUntil <= 0) minutesUntil += 7 * 1440
                    if (soonestMinutes == null || minutesUntil < soonestMinutes) {
                        soonestMinutes = minutesUntil
                    }
                }
            }
            val minutesUntilMidnight = 1440 - nowMinutes
            if (minutesUntilMidnight > 0 && (soonestMinutes == null || minutesUntilMidnight < soonestMinutes)) {
                soonestMinutes = minutesUntilMidnight
            }
            val secondsIntoMinute =
                now.get(Calendar.SECOND) * 1000L + now.get(Calendar.MILLISECOND)
            // One second past the boundary so the widget reads the new state.
            return now.timeInMillis - secondsIntoMinute +
                soonestMinutes!! * 60_000L + 1_000L
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

        /** Occurrence of [item] at [dayDifference] days from today is marked? */
        private fun isMarked(item: ScheduledWidgetClass, dayDifference: Int): Boolean {
            if (item.markedDates.isEmpty()) return false
            val date = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, dayDifference) }
            return dateKey(date) in item.markedDates
        }

        private fun findNextClass(
            classes: List<ScheduledWidgetClass>,
            now: Calendar,
        ): NextWidgetClass? {
            if (classes.isEmpty()) return null

            val today = when (now.get(Calendar.DAY_OF_WEEK)) {
                Calendar.SUNDAY -> 7
                else -> now.get(Calendar.DAY_OF_WEEK) - 1
            }
            val nowMinutes =
                now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val millisIntoMinute =
                now.get(Calendar.SECOND) * 1000L + now.get(Calendar.MILLISECOND)

            val live = classes.firstOrNull { item ->
                item.day == today &&
                    item.startMinutes <= nowMinutes &&
                    nowMinutes < item.endMinutes &&
                    !isMarked(item, 0)
            }
            if (live != null) {
                return NextWidgetClass(
                    item = live,
                    isHappeningNow = true,
                    millisToBoundary = (live.endMinutes - nowMinutes) * 60_000L -
                        millisIntoMinute,
                )
            }

            val next = classes
                .filter { !(it.day == today && isMarked(it, 0)) }
                .minByOrNull { item ->
                    val dayDifference = (item.day - today + 7) % 7
                    var minutesUntil =
                        dayDifference * 1440 + item.startMinutes - nowMinutes
                    if (minutesUntil <= 0) minutesUntil += 7 * 1440
                    minutesUntil
                } ?: return null
            val dayDifference = (next.day - today + 7) % 7
            if (isMarked(next, dayDifference)) return null
            var minutesUntil = dayDifference * 1440 + next.startMinutes - nowMinutes
            if (minutesUntil <= 0) minutesUntil += 7 * 1440
            return NextWidgetClass(
                item = next,
                isHappeningNow = false,
                millisToBoundary = minutesUntil * 60_000L - millisIntoMinute,
            )
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
            val today = when (now.get(Calendar.DAY_OF_WEEK)) {
                Calendar.SUNDAY -> 7
                else -> now.get(Calendar.DAY_OF_WEEK) - 1
            }
            val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val todayKey = dateKey(now)

            val heightDp = manager
                .getAppWidgetOptions(appWidgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val compactLegacy = heightDp in 1 until COMPACT_MAX_HEIGHT_DP
            val showCalendar = heightDp == 0 || heightDp >= CALENDAR_MIN_HEIGHT_DP
            val maxCards = when {
                heightDp == 0 || heightDp >= CARDS_MIN_HEIGHT_DP -> 2
                heightDp >= CALENDAR_MIN_HEIGHT_DP -> 1
                else -> 0
            }
            val showNextCard = heightDp == 0 || heightDp >= NEXT_CARD_MIN_HEIGHT_DP

            val markedTodayCount = classes.count { it.day == today && todayKey in it.markedDates }
            val todayClasses = classes.filter { it.day == today && todayKey !in it.markedDates }
            val liveClass = todayClasses.firstOrNull {
                it.startMinutes <= nowMinutes && nowMinutes < it.endMinutes
            }
            val upcomingToday = todayClasses
                .filter { it.startMinutes > nowMinutes }
                .sortedBy { it.startMinutes }
            val allDoneToday = todayClasses.isNotEmpty() &&
                todayClasses.all { it.endMinutes <= nowMinutes }
            val freeDay = todayClasses.isEmpty()
            val next = findNextClass(classes, now)

            when {
                classes.isEmpty() -> showEmpty(views)

                liveClass != null && !compactLegacy -> {
                    showInClass(context, views, liveClass, nowMinutes)
                }

                liveClass != null -> {
                    showCompactActive(
                        context, views,
                        label = context.getString(R.string.next_class_widget_in_class),
                        whenText = context.getString(
                            R.string.next_class_widget_ends_in,
                            formatCountdown((liveClass.endMinutes - nowMinutes) * 60_000L),
                        ),
                        item = liveClass,
                    )
                }

                upcomingToday.isNotEmpty() && !compactLegacy -> {
                    showUpcoming(
                        context, views, now,
                        nextClass = upcomingToday.first(),
                        remaining = upcomingToday,
                        maxCards = maxCards,
                        showCalendar = showCalendar,
                    )
                }

                upcomingToday.isNotEmpty() -> {
                    val item = upcomingToday.first()
                    val minutesUntil = item.startMinutes - nowMinutes
                    showCompactActive(
                        context, views,
                        label = context.getString(R.string.next_class_widget_label),
                        whenText = context.getString(
                            R.string.next_class_widget_starts_in,
                            formatCountdown(minutesUntil * 60_000L),
                        ),
                        item = item,
                    )
                }

                next != null && (allDoneToday || freeDay) -> {
                    showAllDone(
                        context, views, now, next,
                        titleRes = if (allDoneToday) {
                            R.string.next_class_widget_all_done_title
                        } else {
                            R.string.next_class_widget_free_day_title
                        },
                        showCard = showNextCard,
                    )
                }

                next != null -> {
                    // Marked-out day: everything today is skipped but the next
                    // occurrence is still ahead. Render the upcoming state.
                    if (compactLegacy) {
                        showCompactActive(
                            context, views,
                            label = context.getString(R.string.next_class_widget_label),
                            whenText = context.getString(
                                R.string.next_class_widget_starts_in,
                                formatCountdown(next.millisToBoundary),
                            ),
                            item = next.item,
                        )
                    } else {
                        showUpcoming(
                            context, views, now,
                            nextClass = next.item,
                            remaining = listOf(next.item),
                            maxCards = maxCards,
                            showCalendar = showCalendar,
                        )
                    }
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
            nextClass: ScheduledWidgetClass,
            remaining: List<ScheduledWidgetClass>,
            maxCards: Int,
            showCalendar: Boolean,
        ) {
            views.showOnly(R.id.container_upcoming)

            // Headline: "Design Class in 8 minutes" / "in 1h 12m" / "in 1d 3h".
            val minutesUntil = ((nextClass.startMinutes -
                (now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)))
                .coerceAtLeast(0))
            val phrase = if (minutesUntil < 60) {
                val count = minutesUntil.coerceAtLeast(1)
                context.resources.getQuantityString(
                    R.plurals.next_class_widget_in_minutes,
                    count,
                    count,
                )
            } else {
                context.getString(
                    R.string.next_class_widget_in_compact,
                    formatCountdown(minutesUntil * 60_000L),
                )
            }
            views.setTextViewText(
                R.id.widget_headline,
                nextClass.subject + " " + phrase,
            )

            // Room CTA pill.
            val room = formatRoom(nextClass.room)
            views.setViewVisibility(
                R.id.widget_cta_pill,
                if (room.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_cta_room, room)

            // Calendar column.
            views.setViewVisibility(
                R.id.widget_cal_section,
                if (showCalendar) View.VISIBLE else View.GONE,
            )
            if (showCalendar) {
                val monthLabel = SimpleDateFormat("MMMM", Locale.getDefault())
                views.setTextViewText(R.id.widget_month_label, monthLabel.format(now.time))
                bindCalendar(context, views, now)
            }

            // Remaining-classes cards.
            val cards = remaining.take(maxCards)
            views.setViewVisibility(
                R.id.widget_cards_section,
                if (cards.isEmpty()) View.GONE else View.VISIBLE,
            )
            bindCard(views, 1, cards.getOrNull(0))
            bindCard(views, 2, cards.getOrNull(1))
        }

        private fun showInClass(
            context: Context,
            views: RemoteViews,
            item: ScheduledWidgetClass,
            nowMinutes: Int,
        ) {
            views.showOnly(R.id.container_inclass)
            views.setTextViewText(
                R.id.widget_inclass_ends,
                context.getString(
                    R.string.next_class_widget_ends_in,
                    formatCountdown((item.endMinutes - nowMinutes) * 60_000L),
                ),
            )
            views.setTextViewText(R.id.widget_inclass_subject, item.subject)
            views.setTextViewText(
                R.id.widget_inclass_time,
                formatMinutes(item.startMinutes) + " - " + formatMinutes(item.endMinutes),
            )

            val room = formatRoom(item.room)
            views.setViewVisibility(
                R.id.widget_inclass_cta,
                if (room.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_inclass_cta_room, room)

            val professor = cleanProfessor(item.professor)
            views.setViewVisibility(
                R.id.widget_inclass_prof_row,
                if (professor.isEmpty()) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_inclass_professor, professor)
        }

        private fun showAllDone(
            context: Context,
            views: RemoteViews,
            now: Calendar,
            next: NextWidgetClass,
            titleRes: Int,
            showCard: Boolean,
        ) {
            views.showOnly(R.id.container_alldone)
            views.setTextViewText(R.id.widget_alldone_title, context.getString(titleRes))
            val weekday = SimpleDateFormat("EEEE", Locale.getDefault()).format(now.time)
            views.setTextViewText(
                R.id.widget_alldone_subtitle,
                context.getString(R.string.next_class_widget_enjoy_rest, weekday),
            )

            views.setViewVisibility(
                R.id.widget_alldone_card,
                if (showCard) View.VISIBLE else View.GONE,
            )
            if (showCard) {
                val dayDifference = (next.item.day - dayOfWeekIndex(now) + 7) % 7
                val dayPill = if (dayDifference == 1) {
                    context.getString(R.string.next_class_widget_day_tomorrow)
                } else {
                    weekdayName(next.item.day)
                }
                views.setTextViewText(R.id.widget_alldone_day_pill, dayPill)
                views.setTextViewText(
                    R.id.widget_alldone_starts,
                    context.getString(
                        R.string.next_class_widget_starts_in,
                        formatCountdown(next.millisToBoundary),
                    ),
                )
                views.setTextViewText(R.id.widget_alldone_subject, next.item.subject)
                views.setTextViewText(
                    R.id.widget_alldone_time,
                    formatMinutes(next.item.startMinutes) + " - " +
                        formatMinutes(next.item.endMinutes),
                )
                views.setTextViewText(R.id.widget_alldone_room, formatRoom(next.item.room))
            }
        }

        private fun showCompactActive(
            context: Context,
            views: RemoteViews,
            label: String,
            whenText: String,
            item: ScheduledWidgetClass,
        ) {
            views.showOnly(R.id.container_active)
            views.setTextViewText(R.id.widget_label, label)
            views.setTextViewText(R.id.widget_when, whenText)
            views.setTextViewText(R.id.widget_subject, item.subject)
            views.setTextViewText(
                R.id.widget_time,
                formatMinutes(item.startMinutes) + " - " + formatMinutes(item.endMinutes),
            )
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

        private fun bindCard(views: RemoteViews, cardNumber: Int, item: ScheduledWidgetClass?) {
            val root = if (cardNumber == 1) R.id.widget_card_1 else R.id.widget_card_2
            if (item == null) {
                views.setViewVisibility(root, View.GONE)
                return
            }
            views.setViewVisibility(root, View.VISIBLE)
            views.setTextViewText(
                root.subjectId(cardNumber), item.subject,
            )
            views.setTextViewText(
                root.roomId(cardNumber), formatRoom(item.room),
            )
            views.setTextViewText(
                root.timeId(cardNumber),
                formatMinutes(item.startMinutes) + " - " + formatMinutes(item.endMinutes),
            )
        }

        private fun Int.subjectId(cardNumber: Int) =
            if (cardNumber == 1) R.id.widget_card_1_subject else R.id.widget_card_2_subject

        private fun Int.roomId(cardNumber: Int) =
            if (cardNumber == 1) R.id.widget_card_1_room else R.id.widget_card_2_room

        private fun Int.timeId(cardNumber: Int) =
            if (cardNumber == 1) R.id.widget_card_1_time else R.id.widget_card_2_time

        private fun dayOfWeekIndex(now: Calendar): Int = when (now.get(Calendar.DAY_OF_WEEK)) {
            Calendar.SUNDAY -> 7
            else -> now.get(Calendar.DAY_OF_WEEK) - 1
        }

        private fun weekdayName(day: Int): String = when (day) {
            1 -> "MONDAY"
            2 -> "TUESDAY"
            3 -> "WEDNESDAY"
            4 -> "THURSDAY"
            5 -> "FRIDAY"
            6 -> "SATURDAY"
            7 -> "SUNDAY"
            else -> ""
        }

        /** "242-B" -> "Class 242-B"; "Lab 2" stays "Lab 2". */
        private fun formatRoom(room: String): String =
            if (room.isBlank()) ""
            else if (Regex("[A-Za-z]{3,}").containsMatchIn(room)) room
            else "Class " + room

        private fun cleanProfessor(professor: String): String =
            professor.takeIf {
                it.isNotBlank() && !it.equals("Not specified", ignoreCase = true)
            }.orEmpty()

        // 24h clock, tabular digits — matches the mockup ("16:00 - 18:00").
        private fun formatMinutes(minutes: Int): String {
            val normalized = minutes.coerceIn(0, 1440)
            val hour = if (normalized == 1440) 24 else normalized / 60
            return String.format(
                Locale.US,
                "%02d:%02d",
                hour,
                normalized % 60,
            )
        }

        private fun formatCountdown(millisToBoundary: Long): String {
            val minutes = ((millisToBoundary.coerceAtLeast(0L) + 59_999L) / 60_000L)
                .toInt()
            if (minutes < 60) return "$minutes min"

            val days = minutes / 1_440
            val hours = (minutes % 1_440) / 60
            val remainingMinutes = minutes % 60
            return when {
                days > 0 && hours > 0 && remainingMinutes > 0 ->
                    "${days}d ${hours}h ${remainingMinutes}m"
                days > 0 && hours > 0 -> "${days}d ${hours}h"
                days > 0 && remainingMinutes > 0 -> "${days}d ${remainingMinutes}m"
                days > 0 -> "${days}d"
                remainingMinutes > 0 -> "${hours}h ${remainingMinutes}m"
                else -> "${hours}h"
            }
        }
    }
}

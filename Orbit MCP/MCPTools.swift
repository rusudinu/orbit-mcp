//
//  MCPTools.swift
//  Orbit MCP
//
//  Static tool descriptors advertised to MCP clients.
//

import Foundation

nonisolated enum MCPTools {

    // MARK: - Shared schemas

    private static let listSchema: [String: Any] = [
        "type": "object",
        "required": ["id", "title", "source", "isDefault"],
        "properties": [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "source": ["type": "string"],
            "colorHex": ["type": ["string", "null"]],
            "isDefault": ["type": "boolean"]
        ],
        "additionalProperties": false
    ]

    private static let reminderSchema: [String: Any] = [
        "type": "object",
        "required": ["id", "title", "listID", "listTitle", "isCompleted", "priority"],
        "properties": [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "notes": ["type": ["string", "null"]],
            "listID": ["type": "string"],
            "listTitle": ["type": "string"],
            "dueDate": ["type": ["string", "null"], "format": "date-time"],
            "isCompleted": ["type": "boolean"],
            "completionDate": ["type": ["string", "null"], "format": "date-time"],
            "priority": ["type": "integer"],
            "url": ["type": ["string", "null"], "format": "uri"],
            "creationDate": ["type": ["string", "null"], "format": "date-time"],
            "lastModifiedDate": ["type": ["string", "null"], "format": "date-time"]
        ],
        "additionalProperties": true
    ]

    private static let messageSchema: [String: Any] = [
        "type": "object",
        "required": ["message"],
        "properties": ["message": ["type": "string"]],
        "additionalProperties": false
    ]

    private static let calendarSchema: [String: Any] = [
        "type": "object",
        "required": ["id", "title", "source", "isDefault", "allowsModification"],
        "properties": [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "source": ["type": "string"],
            "colorHex": ["type": ["string", "null"]],
            "allowsModification": ["type": "boolean"],
            "isDefault": ["type": "boolean"]
        ],
        "additionalProperties": false
    ]

    private static let eventSchema: [String: Any] = [
        "type": "object",
        "required": ["id", "title", "calendarID", "calendarTitle", "isAllDay"],
        "properties": [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "notes": ["type": ["string", "null"]],
            "location": ["type": ["string", "null"]],
            "url": ["type": ["string", "null"], "format": "uri"],
            "start": ["type": ["string", "null"], "format": "date-time"],
            "end": ["type": ["string", "null"], "format": "date-time"],
            "isAllDay": ["type": "boolean"],
            "calendarID": ["type": "string"],
            "calendarTitle": ["type": "string"],
            "creationDate": ["type": ["string", "null"], "format": "date-time"],
            "lastModifiedDate": ["type": ["string", "null"], "format": "date-time"]
        ],
        "additionalProperties": true
    ]

    private static let folderSchema: [String: Any] = [
        "type": "object",
        "required": ["id", "name", "accountName"],
        "properties": [
            "id": ["type": "string"],
            "name": ["type": "string"],
            "accountName": ["type": "string"]
        ],
        "additionalProperties": false
    ]

    private static let notesAccountSchema: [String: Any] = [
        "type": "object",
        "required": ["name", "folders"],
        "properties": [
            "name": ["type": "string"],
            "folders": [
                "type": "array",
                "items": folderSchema
            ]
        ],
        "additionalProperties": false
    ]

    private static let notesStructureSchema: [String: Any] = [
        "type": "object",
        "required": ["accounts"],
        "properties": [
            "accounts": [
                "type": "array",
                "items": notesAccountSchema
            ]
        ],
        "additionalProperties": false
    ]

    private static let noteSummarySchema: [String: Any] = [
        "type": "object",
        "required": ["id", "title", "folderName", "accountName"],
        "properties": [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "folderName": ["type": "string"],
            "accountName": ["type": "string"],
            "creationDate": ["type": ["string", "null"], "format": "date-time"],
            "modificationDate": ["type": ["string", "null"], "format": "date-time"],
            "body": ["type": ["string", "null"]]
        ],
        "additionalProperties": true
    ]

    private static let noteSchema: [String: Any] = [
        "type": "object",
        "required": ["id", "title", "folderName", "accountName", "plainBody", "htmlBody"],
        "properties": [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "folderName": ["type": "string"],
            "accountName": ["type": "string"],
            "creationDate": ["type": ["string", "null"], "format": "date-time"],
            "modificationDate": ["type": ["string", "null"], "format": "date-time"],
            "plainBody": ["type": "string"],
            "htmlBody": ["type": "string"]
        ],
        "additionalProperties": true
    ]

    private static let timeInfoSchema: [String: Any] = [
        "type": "object",
        "required": [
            "iso8601", "date", "time", "timezone", "timezoneOffsetSeconds",
            "timezoneOffsetString", "dayOfWeek", "dayOfWeekNumber",
            "dayOfMonth", "dayOfYear", "weekOfYear", "month", "monthName",
            "year", "unixSeconds", "unixMilliseconds", "isDST"
        ],
        "properties": [
            "iso8601": ["type": "string", "format": "date-time"],
            "date": ["type": "string"],
            "time": ["type": "string"],
            "timezone": ["type": "string"],
            "timezoneAbbreviation": ["type": ["string", "null"]],
            "timezoneOffsetSeconds": ["type": "integer"],
            "timezoneOffsetString": ["type": "string"],
            "dayOfWeek": ["type": "string"],
            "dayOfWeekNumber": ["type": "integer", "description": "1 = Monday … 7 = Sunday (ISO-8601)."],
            "dayOfMonth": ["type": "integer"],
            "dayOfYear": ["type": "integer"],
            "weekOfYear": ["type": "integer"],
            "month": ["type": "integer"],
            "monthName": ["type": "string"],
            "year": ["type": "integer"],
            "unixSeconds": ["type": "integer"],
            "unixMilliseconds": ["type": "integer"],
            "isDST": ["type": "boolean"]
        ],
        "additionalProperties": true
    ]

    private static let timeDiffSchema: [String: Any] = [
        "type": "object",
        "required": [
            "totalSeconds", "totalMinutes", "totalHours", "totalDays",
            "years", "months", "days", "hours", "minutes", "seconds",
            "humanized", "direction"
        ],
        "properties": [
            "totalSeconds": ["type": "number"],
            "totalMinutes": ["type": "number"],
            "totalHours": ["type": "number"],
            "totalDays": ["type": "number"],
            "years": ["type": "integer"],
            "months": ["type": "integer"],
            "days": ["type": "integer"],
            "hours": ["type": "integer"],
            "minutes": ["type": "integer"],
            "seconds": ["type": "integer"],
            "humanized": ["type": "string"],
            "direction": ["type": "string", "enum": ["future", "past", "now"]]
        ],
        "additionalProperties": false
    ]

    private static let formattedTimeSchema: [String: Any] = [
        "type": "object",
        "required": ["formatted", "timezone", "locale"],
        "properties": [
            "formatted": ["type": "string"],
            "timezone": ["type": "string"],
            "locale": ["type": "string"]
        ],
        "additionalProperties": false
    ]

    private static func listOf(_ schema: [String: Any]) -> [String: Any] {
        return [
            "type": "object",
            "required": ["items"],
            "properties": [
                "items": [
                    "type": "array",
                    "items": schema
                ]
            ],
            "additionalProperties": false
        ]
    }

    // MARK: - Tool descriptors

    nonisolated static let descriptors: [[String: Any]] = [
        [
            "name": "reminders_list_lists",
            "title": "List Reminder Lists",
            "description": "Return every Reminders list (calendar) the user has, including its identifier, source, color, and which one is the default for new reminders.",
            "inputSchema": [
                "type": "object",
                "properties": [:],
                "additionalProperties": false
            ],
            "outputSchema": listOf(listSchema)
        ],
        [
            "name": "reminders_search",
            "title": "Search Reminders",
            "description": "Search and filter reminders. Supports filtering by list, completion state, due date range, and a free-text query against title and notes.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "listIds": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Restrict to these reminder list identifiers (from reminders_list_lists)."
                    ],
                    "includeCompleted": [
                        "type": "boolean",
                        "description": "Include completed reminders. Default false.",
                        "default": false
                    ],
                    "dueAfter": [
                        "type": "string",
                        "description": "ISO-8601 timestamp; only return items due on or after this date.",
                        "format": "date-time"
                    ],
                    "dueBefore": [
                        "type": "string",
                        "description": "ISO-8601 timestamp; only return items due on or before this date.",
                        "format": "date-time"
                    ],
                    "query": [
                        "type": "string",
                        "description": "Case-insensitive substring matched against title and notes."
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of items to return.",
                        "minimum": 1
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": listOf(reminderSchema)
        ],
        [
            "name": "reminders_get",
            "title": "Get Reminder",
            "description": "Fetch a single reminder by its identifier.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": [
                    "id": ["type": "string", "description": "Reminder identifier."]
                ],
                "additionalProperties": false
            ],
            "outputSchema": reminderSchema
        ],
        [
            "name": "reminders_create",
            "title": "Create Reminder",
            "description": "Create a new reminder. Defaults to the user's default Reminders list when listId is omitted.",
            "inputSchema": [
                "type": "object",
                "required": ["title"],
                "properties": [
                    "title": ["type": "string"],
                    "notes": ["type": "string"],
                    "listId": [
                        "type": "string",
                        "description": "Identifier (or title) of the target list."
                    ],
                    "dueDate": [
                        "type": "string",
                        "description": "ISO-8601 due date.",
                        "format": "date-time"
                    ],
                    "priority": [
                        "type": "integer",
                        "description": "0 = none, 1 = high, 5 = medium, 9 = low.",
                        "minimum": 0,
                        "maximum": 9
                    ],
                    "url": ["type": "string", "format": "uri"]
                ],
                "additionalProperties": false
            ],
            "outputSchema": reminderSchema
        ],
        [
            "name": "reminders_update",
            "title": "Update Reminder",
            "description": "Update a reminder's fields. Only fields that are present in the call are modified. Pass null to clear notes, dueDate, priority, or url.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": [
                    "id": ["type": "string"],
                    "title": ["type": "string"],
                    "notes": ["type": ["string", "null"]],
                    "dueDate": ["type": ["string", "null"], "format": "date-time"],
                    "priority": ["type": ["integer", "null"], "minimum": 0, "maximum": 9],
                    "url": ["type": ["string", "null"], "format": "uri"],
                    "listId": ["type": "string", "description": "Move the reminder to this list."],
                    "completed": ["type": "boolean"]
                ],
                "additionalProperties": false
            ],
            "outputSchema": reminderSchema
        ],
        [
            "name": "reminders_complete",
            "title": "Complete Reminder",
            "description": "Mark a reminder as completed (or uncompleted) without touching other fields.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": [
                    "id": ["type": "string"],
                    "completed": [
                        "type": "boolean",
                        "default": true,
                        "description": "Whether to mark as completed. Pass false to un-complete."
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": reminderSchema
        ],
        [
            "name": "reminders_delete",
            "title": "Delete Reminder",
            "description": "Permanently delete a reminder by identifier.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": [
                    "id": ["type": "string"]
                ],
                "additionalProperties": false
            ],
            "outputSchema": messageSchema
        ],

        // MARK: Calendar

        [
            "name": "calendar_list_calendars",
            "title": "List Calendars",
            "description": "Return every Calendar (account/source pair) the user has, including which one is the default for new events.",
            "inputSchema": [
                "type": "object",
                "properties": [:],
                "additionalProperties": false
            ],
            "outputSchema": listOf(calendarSchema)
        ],
        [
            "name": "calendar_search",
            "title": "Search Events",
            "description": "Fetch calendar events occurring between two timestamps. Supports filtering by calendar IDs and a free-text query against title/notes/location.",
            "inputSchema": [
                "type": "object",
                "required": ["start", "end"],
                "properties": [
                    "start": ["type": "string", "format": "date-time", "description": "ISO-8601 lower bound."],
                    "end": ["type": "string", "format": "date-time", "description": "ISO-8601 upper bound (max 4 years after start)."],
                    "calendarIds": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Restrict to these calendar identifiers (from calendar_list_calendars)."
                    ],
                    "query": ["type": "string", "description": "Case-insensitive substring matched against title, notes, and location."],
                    "limit": ["type": "integer", "minimum": 1]
                ],
                "additionalProperties": false
            ],
            "outputSchema": listOf(eventSchema)
        ],
        [
            "name": "calendar_get",
            "title": "Get Event",
            "description": "Fetch a single calendar event by its identifier.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": ["id": ["type": "string"]],
                "additionalProperties": false
            ],
            "outputSchema": eventSchema
        ],
        [
            "name": "calendar_create",
            "title": "Create Event",
            "description": "Create a new calendar event. Defaults to the user's default calendar when calendarId is omitted.",
            "inputSchema": [
                "type": "object",
                "required": ["title", "start", "end"],
                "properties": [
                    "title": ["type": "string"],
                    "notes": ["type": "string"],
                    "location": ["type": "string"],
                    "url": ["type": "string", "format": "uri"],
                    "start": ["type": "string", "format": "date-time"],
                    "end": ["type": "string", "format": "date-time"],
                    "allDay": ["type": "boolean", "default": false],
                    "calendarId": ["type": "string", "description": "Identifier or title of the target calendar."]
                ],
                "additionalProperties": false
            ],
            "outputSchema": eventSchema
        ],
        [
            "name": "calendar_update",
            "title": "Update Event",
            "description": "Update fields on a calendar event. Only fields that are present in the call are modified. Pass null to clear notes, location, or url.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": [
                    "id": ["type": "string"],
                    "title": ["type": "string"],
                    "notes": ["type": ["string", "null"]],
                    "location": ["type": ["string", "null"]],
                    "url": ["type": ["string", "null"], "format": "uri"],
                    "start": ["type": "string", "format": "date-time"],
                    "end": ["type": "string", "format": "date-time"],
                    "allDay": ["type": "boolean"],
                    "calendarId": ["type": "string"]
                ],
                "additionalProperties": false
            ],
            "outputSchema": eventSchema
        ],
        [
            "name": "calendar_delete",
            "title": "Delete Event",
            "description": "Permanently delete a calendar event by identifier. For recurring events this deletes only this occurrence.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": ["id": ["type": "string"]],
                "additionalProperties": false
            ],
            "outputSchema": messageSchema
        ],

        // MARK: Notes

        [
            "name": "notes_list_folders",
            "title": "List Notes Accounts and Folders",
            "description": "Return every Notes account and its folders. Use folder IDs from this call when creating or scoping searches to a folder.",
            "inputSchema": [
                "type": "object",
                "properties": [:],
                "additionalProperties": false
            ],
            "outputSchema": notesStructureSchema
        ],
        [
            "name": "notes_search",
            "title": "Search Notes",
            "description": "List notes, optionally scoped to an account or folder, optionally matched by a substring against title/body.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "folderId": ["type": "string", "description": "Identifier of the folder to search in (from notes_list_folders)."],
                    "accountName": ["type": "string", "description": "Limit search to this account when no folderId is given."],
                    "query": ["type": "string", "description": "Case-insensitive substring matched against title and plaintext body."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 500, "default": 50],
                    "includeBody": [
                        "type": "boolean",
                        "default": false,
                        "description": "If true, include the plaintext body of each note in the result."
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": listOf(noteSummarySchema)
        ],
        [
            "name": "notes_get",
            "title": "Get Note",
            "description": "Fetch a single note by identifier including its plaintext and HTML body.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": ["id": ["type": "string"]],
                "additionalProperties": false
            ],
            "outputSchema": noteSchema
        ],
        [
            "name": "notes_create",
            "title": "Create Note",
            "description": "Create a new note. Defaults to the user's default folder when folderId is omitted.",
            "inputSchema": [
                "type": "object",
                "required": ["title"],
                "properties": [
                    "title": ["type": "string"],
                    "body": ["type": "string", "description": "Plaintext body. Newlines are preserved."],
                    "folderId": ["type": "string", "description": "Identifier of the target folder (from notes_list_folders)."],
                    "folderName": ["type": "string", "description": "Title of the target folder. Used if folderId is omitted."],
                    "accountName": ["type": "string", "description": "Restrict folderName lookup to this account."]
                ],
                "additionalProperties": false
            ],
            "outputSchema": noteSchema
        ],
        [
            "name": "notes_update",
            "title": "Update Note",
            "description": "Replace title and/or body of an existing note.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": [
                    "id": ["type": "string"],
                    "title": ["type": "string"],
                    "body": ["type": "string"]
                ],
                "additionalProperties": false
            ],
            "outputSchema": noteSchema
        ],
        [
            "name": "notes_delete",
            "title": "Delete Note",
            "description": "Permanently delete a note by identifier.",
            "inputSchema": [
                "type": "object",
                "required": ["id"],
                "properties": ["id": ["type": "string"]],
                "additionalProperties": false
            ],
            "outputSchema": messageSchema
        ],

        // MARK: Time

        [
            "name": "time_now",
            "title": "Get Current Date and Time",
            "description": "Return the current date and time on this Mac, including weekday, ISO-8601 timestamp with timezone offset, and Unix epoch. Use this whenever you need to know what 'today' or 'now' is. Pass `timezone` to get the result in a specific IANA timezone.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "timezone": [
                        "type": "string",
                        "description": "IANA timezone identifier (e.g. 'America/New_York', 'Europe/Berlin', 'UTC'). Defaults to the system timezone."
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": timeInfoSchema
        ],
        [
            "name": "time_convert",
            "title": "Convert Between Timezones",
            "description": "Convert a timestamp into another timezone. The input may include an explicit offset (e.g. 'Z' or '+02:00') or use `fromTimezone` for inputs without an offset.",
            "inputSchema": [
                "type": "object",
                "required": ["time", "toTimezone"],
                "properties": [
                    "time": [
                        "type": "string",
                        "description": "ISO-8601 timestamp to convert. May be 'YYYY-MM-DD', 'YYYY-MM-DDTHH:mm:ss', or include an offset."
                    ],
                    "toTimezone": [
                        "type": "string",
                        "description": "Target IANA timezone identifier (e.g. 'America/Los_Angeles')."
                    ],
                    "fromTimezone": [
                        "type": "string",
                        "description": "Source IANA timezone, used only when `time` has no explicit offset."
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": timeInfoSchema
        ],
        [
            "name": "time_add",
            "title": "Add Duration to a Time",
            "description": "Add (or subtract, with negative values) a calendar-aware duration to a timestamp. Useful for 'tomorrow at 9am', 'in 3 weeks', 'two months ago', etc.",
            "inputSchema": [
                "type": "object",
                "required": ["time"],
                "properties": [
                    "time": [
                        "type": "string",
                        "description": "ISO-8601 starting timestamp. Use `time_now` first if you want to start from now."
                    ],
                    "years": ["type": "integer"],
                    "months": ["type": "integer"],
                    "weeks": ["type": "integer"],
                    "days": ["type": "integer"],
                    "hours": ["type": "integer"],
                    "minutes": ["type": "integer"],
                    "seconds": ["type": "integer"],
                    "timezone": [
                        "type": "string",
                        "description": "IANA timezone for calendar arithmetic (DST-aware). Defaults to the system timezone."
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": timeInfoSchema
        ],
        [
            "name": "time_diff",
            "title": "Compute Difference Between Two Times",
            "description": "Compute the difference between two timestamps, broken down into years/months/days/hours/minutes/seconds plus totals and a humanized string. `direction` indicates whether `to` is in the future or past relative to `from`.",
            "inputSchema": [
                "type": "object",
                "required": ["from", "to"],
                "properties": [
                    "from": ["type": "string", "description": "ISO-8601 start timestamp."],
                    "to": ["type": "string", "description": "ISO-8601 end timestamp."],
                    "timezone": [
                        "type": "string",
                        "description": "IANA timezone used for calendar component math. Defaults to the system timezone."
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": timeDiffSchema
        ],
        [
            "name": "time_format",
            "title": "Format a Time for Display",
            "description": "Render a timestamp using either named styles (none/short/medium/long/full) or a custom DateFormatter pattern (e.g. \"EEEE, MMMM d 'at' h:mm a\").",
            "inputSchema": [
                "type": "object",
                "required": ["time"],
                "properties": [
                    "time": ["type": "string", "description": "ISO-8601 timestamp."],
                    "dateStyle": [
                        "type": "string",
                        "enum": ["none", "short", "medium", "long", "full"],
                        "description": "Named style for the date component. Ignored if `pattern` is set."
                    ],
                    "timeStyle": [
                        "type": "string",
                        "enum": ["none", "short", "medium", "long", "full"],
                        "description": "Named style for the time component. Ignored if `pattern` is set."
                    ],
                    "pattern": [
                        "type": "string",
                        "description": "Custom DateFormatter pattern. When provided, overrides dateStyle/timeStyle."
                    ],
                    "locale": [
                        "type": "string",
                        "description": "BCP-47/POSIX locale identifier (e.g. 'en_US', 'fr_FR'). Defaults to the system locale."
                    ],
                    "timezone": [
                        "type": "string",
                        "description": "IANA timezone identifier. Defaults to the system timezone."
                    ]
                ],
                "additionalProperties": false
            ],
            "outputSchema": formattedTimeSchema
        ]
    ]
}

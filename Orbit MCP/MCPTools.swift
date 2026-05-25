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
        ]
    ]
}

# Pomodoro worklogging language

Pomodoro turns timed Calendar events into Whistler worklogs. These terms distinguish work, non-working time, and differently named references to the same project.

## Language

**Skip rule**:
A selected condition that excludes a Calendar event from loggable work. Any enabled matching rule excludes the event; an unchecked matching custom rule prevents old AI instructions from silently excluding its title again.
_Avoid_: Blacklist, ignore list

**Project alias**:
An alternative Calendar label for one Whistler project, such as “Opeone to Quotomy” for “quotomy.” The alias belongs to an account and does not rename the project.
_Avoid_: Project nickname, renamed project

**Work category**:
A user-chosen kind of work, such as Meetings or Implementation, shared across projects. Its optional description explains when it applies; it is distinct from the project the work belongs to.
_Avoid_: Classification class, task type

**Project focus**:
A focus session explicitly attributed to a chosen Whistler project, rather than continuing preceding work. An optional note describes the work within that project.
_Avoid_: Focus continuation, project nickname

**Focus continuation**:
An unnamed Calendar Focus time block that adds time to preceding accepted work without becoming a separate task. A named block or an explicit project alias is not a generic continuation.
_Avoid_: Duplicate task, focus task

**Work anchor**:
The most recent Calendar event accepted as work, to which generic focus continuations belong. Skipped events are not work anchors.
_Avoid_: Previous event, previous task

**Out-of-office event**:
A Calendar status representing non-working time in this workflow, not merely work performed away from an office.
_Avoid_: Remote work, working location

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

## Feedback language

**Observation note**:
A lead's rough, dated note about one member, written whenever something happens. Notes are the only source of facts in feedback.
_Avoid_: Feedback, comment

**Performance level**:
One of the feedback form's five fields, from Exceptional Performance to Needs significant improvement, judged against the member's own level and the levels on either side.
_Avoid_: Rating, score, grade

**Grade**:
A member's place on their ladder (JE … Staff for engineering; Specialist … System owner for BizOps), derived from their title.
_Avoid_: Level (reserved for performance level), rank

**Role**:
One of the form groups a member is listed under, with that group's competencies. Most members have one; an ETM also on the engineer list has two, and each role is its own form response.
_Avoid_: Group (the form's question), department

**Feedback item**:
One numbered line in a performance-level field: a competency tag and one SBI sentence reworded from one observation note.
_Avoid_: Bullet, point

**Clarification**:
A question the user must answer or dismiss before the form opens: an unclear competency or level, a missing SBI part, a missing suggestion for something to improve, or a number or absolute word the note never said.
_Avoid_: Warning, error

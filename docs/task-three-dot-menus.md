# Task 3-dot menus — by state

Summary of all 3-dot (ellipsis) menu items for tasks in the Tasks list, grouped by when they appear.

---

## When task is **processing** (agent running)

Only the 3-dot menu is shown; one item:

| Label | Icon |
|-------|------|
| Stop | `stop.fill` |

---

## When task has a **linked agent** (not processing)

| Label | Icon |
|-------|------|
| Review | `person` |
| Continue | `play.fill` |
| Reset agent | `arrow.counterclockwise` |

*(Divider, then the rest of the menu below.)*

---

## When task is **stopped** (agent was stopped)

Same agent block as above:

| Label | Icon |
|-------|------|
| Review | `person` |
| Continue | `play.fill` |
| Reset agent | `arrow.counterclockwise` |

---

## **Incomplete** tasks (not done)

Common actions (shown when applicable):

| Label | Icon | When shown |
|-------|------|------------|
| Delegate | `person` | In progress, no agent linked |
| Edit | `pencil` | Task is editable |
| Backlog | `tray.full` | When viewing In Progress list |
| Move to In Progress | `arrow.right.circle` | When viewing Backlog list |
| Complete | `checkmark.circle` | Always for incomplete tasks |

---

## **Completed** tasks

| Label | Icon |
|-------|------|
| Mark as not done | `circle` |
| Delete | `trash` *(destructive)* |

---

## **All** task rows (always in menu)

| Label | Icon |
|-------|------|
| Complete / Mark as not done | `checkmark.circle` / `circle` |
| Delete | `trash` *(destructive)* |

---

## **Deleted** tasks (trash)

Separate row type; its own 3-dot and context menu:

| Label | Icon |
|-------|------|
| Restore | `arrow.uturn.backward` |
| Delete permanently | `trash` *(destructive)* |

---

## Summary by state

| State | Menu focus |
|-------|------------|
| **Processing** | Stop only |
| **Stopped / linked agent** | Review, Continue, Reset agent |
| **In progress (no agent)** | Delegate, Edit, Backlog, Complete, Delete |
| **Backlog** | Delegate, Edit, Move to In Progress, Complete, Delete |
| **Completed** | Mark as not done, Delete |
| **Deleted (trash)** | Restore, Delete permanently |

---

*Source: `Views/MainWindow/TasksListView.swift` — `TaskRowView` Menu/contextMenu and `deletedTaskRow` Menu.*

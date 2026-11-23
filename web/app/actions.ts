"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { dbErrorMessage } from "@/lib/db";
import { withFlash, type FlashKind } from "@/lib/flash";
import * as Q from "@/lib/queries";
import { createSession, destroySession, MIN_PASSWORD_LENGTH, requireAdmin, requireUser } from "@/lib/session";

function str(fd: FormData, key: string) {
  return String(fd.get(key) ?? "").trim();
}

async function postedFrom() {
  const referer = (await headers()).get("referer");
  if (!referer) return "/";
  const url = new URL(referer);
  return url.pathname + url.search;
}

type Outcome = string | { message: string; goTo: string };

async function settle(mutation: () => Promise<Outcome>): Promise<never> {
  let target = await postedFrom();
  let flash: [FlashKind, string];
  try {
    const outcome = await mutation();
    if (typeof outcome === "string") flash = ["ok", outcome];
    else [target, flash] = [outcome.goTo, ["ok", outcome.message]];
  } catch (e) {
    flash = ["error", dbErrorMessage(e)];
  }
  revalidatePath("/", "layout");
  redirect(withFlash(target, ...flash));
}

// ---------------------------------------------------------------- auth

export async function login(fd: FormData) {
  const { rows } = await Q.login.run(str(fd, "email"), str(fd, "password"));
  if (!rows[0]) redirect(withFlash("/login", "error", "Invalid email or password"));
  await createSession(rows[0].user_id);
  const { rows: [user] } = await Q.userById.run(rows[0].user_id);
  redirect(user.role === "ADMIN" ? "/admin" : "/");
}

export async function register(fd: FormData) {
  await settle(async () => {
    if (str(fd, "password").length < MIN_PASSWORD_LENGTH)
      throw new Error(`Password must be at least ${MIN_PASSWORD_LENGTH} characters`);
    const { rows } = await Q.register.run(str(fd, "name"), str(fd, "email"), str(fd, "password"));
    await createSession(rows[0].user_id);
    return { message: "Welcome! Enroll in your courses to get started.", goTo: "/courses" };
  });
}

export async function logout() {
  await destroySession();
  redirect("/login");
}

// ---------------------------------------------------------------- tasks

export async function addTask(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    await Q.addTask.run(
      user.user_id,
      Number(str(fd, "course_id")),
      str(fd, "title"),
      str(fd, "description") || null,
      str(fd, "task_type"),
      str(fd, "deadline"),
      Number(str(fd, "estimated_hours")),
      Number(str(fd, "priority")),
      fd.getAll("prereqs").map(Number),
      Number(str(fd, "team_id")) || null,
    );
    return "Task added";
  });
}

export async function completeTask(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    await Q.completeTask.run(user.user_id, Number(str(fd, "task_id")));
    return "Task completed";
  });
}

export async function rescheduleTask(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rows } = await Q.rescheduleTask.run(
      user.user_id,
      Number(str(fd, "task_id")),
      str(fd, "deadline"),
      fd.get("cascade") === "on",
    );
    const n = rows[0].p_shifted;
    return `Deadline updated (${n} task${n === 1 ? "" : "s"} moved)`;
  });
}

export async function deleteTask(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rowCount } = await Q.deleteTask.run(Number(str(fd, "task_id")), user.user_id);
    if (rowCount === 0) throw new Error("Task not found");
    return { message: "Task deleted", goTo: "/tasks" };
  });
}

// ---------------------------------------------------------------- courses

export async function enroll(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    await Q.enroll.run(user.user_id, Number(str(fd, "course_id")));
    return "Enrolled";
  });
}

// ---------------------------------------------------------------- teams

export async function createTeam(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    await Q.createTeam.run(user.user_id, Number(str(fd, "course_id")), str(fd, "name"));
    return "Team created";
  });
}

export async function addTeamMember(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rowCount } = await Q.addTeamMember.run(
      user.user_id,
      Number(str(fd, "team_id")),
      str(fd, "name"),
      str(fd, "srn") || null,
      str(fd, "email") || null,
      str(fd, "phone") || null,
      str(fd, "role"),
    );
    if (rowCount === 0) throw new Error("Team not found");
    return "Teammate added";
  });
}

export async function removeTeamMember(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rowCount } = await Q.removeTeamMember.run(user.user_id, Number(str(fd, "member_id")));
    if (rowCount === 0) throw new Error("Teammate not found");
    return "Teammate removed";
  });
}

// ---------------------------------------------------------------- availability

export async function setPattern(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    await Q.setPattern.run(
      user.user_id,
      str(fd, "from"),
      str(fd, "to"),
      Number(str(fd, "weekday")),
      Number(str(fd, "weekend")),
    );
    return "Availability pattern applied";
  });
}

export async function saveDays(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    await Q.saveDays.run(user.user_id, fd.getAll("day").map(String), fd.getAll("hours").map(Number));
    return "Availability saved";
  });
}

// ---------------------------------------------------------------- notes

function lines(fd: FormData, key: string, sep: RegExp) {
  return str(fd, key).split(sep).map((s) => s.trim()).filter(Boolean);
}

export async function addNote(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rowCount } = await Q.addNote.run(
      user.user_id,
      Number(str(fd, "task_id")),
      str(fd, "text"),
      lines(fd, "tags", /,/),
      lines(fd, "checklist", /\n/),
    );
    if (rowCount === 0) throw new Error("Task not found");
    return "Note saved";
  });
}

export async function toggleNoteItem(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rowCount } = await Q.toggleNoteItem.run(user.user_id, Number(str(fd, "note_id")), Number(str(fd, "index")));
    if (rowCount === 0) throw new Error("Checklist item not found");
    return "Checklist updated";
  });
}

export async function addNoteTag(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rowCount } = await Q.addNoteTag.run(user.user_id, Number(str(fd, "note_id")), str(fd, "tag"));
    return rowCount === 0 ? "Tag already there" : "Tag added";
  });
}

export async function removeNoteTag(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    await Q.removeNoteTag.run(user.user_id, Number(str(fd, "note_id")), str(fd, "tag"));
    return "Tag removed";
  });
}

export async function deleteNote(fd: FormData) {
  const user = await requireUser();
  await settle(async () => {
    const { rowCount } = await Q.deleteNote.run(user.user_id, Number(str(fd, "note_id")));
    if (rowCount === 0) throw new Error("Note not found");
    return "Note deleted";
  });
}

// ---------------------------------------------------------------- admin

export async function adminSetRole(fd: FormData) {
  const user = await requireAdmin();
  await settle(async () => {
    await Q.adminSetRole.run(user.user_id, Number(str(fd, "user_id")), str(fd, "role"));
    return "Role updated";
  });
}

export async function adminAddCourse(fd: FormData) {
  const user = await requireAdmin();
  await settle(async () => {
    await Q.adminAddCourse.run(
      user.user_id,
      str(fd, "course_code"),
      str(fd, "course_name"),
      str(fd, "course_type"),
      Number(str(fd, "semester")),
      Number(str(fd, "credits")),
      str(fd, "description"),
    );
    return "Course added";
  });
}

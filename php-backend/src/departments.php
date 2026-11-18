<?php
// src/departments.php
// Departments are a relation: users, events, and offices store department_id,
// while every wire payload keeps carrying the name. These helpers translate in
// both directions so one spelling of a department exists once.

declare(strict_types=1);

/// Resolves a department name to its id, creating the row when needed.
/// Blank names mean "school-wide" and return null. The unique key is
/// utf8mb4_unicode_ci, so "IT" and "it" resolve to the same row.
function department_id_for(?string $name, bool $create = true): ?int
{
    $trimmed = trim((string)$name);
    if ($trimmed === '') {
        return null;
    }

    $row = fetch_one('SELECT id FROM departments WHERE name = ? LIMIT 1', [$trimmed]);
    if ($row !== null) {
        return (int)$row['id'];
    }
    if (!$create) {
        return null;
    }

    try {
        query('INSERT INTO departments (name) VALUES (?)', [$trimmed]);
        return (int)db()->lastInsertId();
    } catch (PDOException $e) {
        // Two simultaneous signups with different spellings of one department:
        // the unique key picks a winner, and the loser reads that row back.
        if ((int)($e->errorInfo[1] ?? 0) !== 1062) {
            throw $e;
        }
        $row = fetch_one('SELECT id FROM departments WHERE name = ? LIMIT 1', [$trimmed]);
        if ($row === null) {
            throw $e;
        }
        return (int)$row['id'];
    }
}

/// Reads the name for a department id; null when the row is gone.
function department_name_for(?int $id): ?string
{
    if ($id === null) {
        return null;
    }
    $row = fetch_one('SELECT name FROM departments WHERE id = ? LIMIT 1', [$id]);
    return $row === null ? null : (string)$row['name'];
}

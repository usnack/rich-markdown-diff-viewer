#!/usr/bin/env node

// 프로젝트 전체에서 agent/skills 디렉터리를 탐색하여, SKILL.md를 가진 스킬을
// Codex와 Claude Code 프로젝트 스킬 디렉터리(.agents/skills, .claude/skills)에 연결합니다.

const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const targetDirs = [
  path.join(projectRoot, ".agents", "skills"),
  path.join(projectRoot, ".claude", "skills"),
];

const IGNORED_DIR_NAMES = new Set([
  "node_modules",
  ".git",
  ".agents",
  ".claude",
]);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function isSymlink(targetPath) {
  try {
    return fs.lstatSync(targetPath).isSymbolicLink();
  } catch (error) {
    if (error.code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

// 프로젝트 전체를 순회하며 "**/agent/skills" 디렉터리를 찾는다.
function findSkillsSourceDirs(dir, results = []) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (error) {
    return results;
  }

  for (const entry of entries) {
    if (!entry.isDirectory() || IGNORED_DIR_NAMES.has(entry.name)) {
      continue;
    }

    const entryPath = path.join(dir, entry.name);

    if (entry.name === "skills" && path.basename(dir) === "agent") {
      results.push(entryPath);
      continue;
    }

    findSkillsSourceDirs(entryPath, results);
  }

  return results;
}

// 각 agent/skills 디렉터리 안에서 SKILL.md를 가진 스킬 디렉터리를 찾는다.
function discoverSkills(skillsSourceDirs) {
  const skills = new Map();

  for (const skillsSourceDir of skillsSourceDirs) {
    const entries = fs.readdirSync(skillsSourceDir, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }

      const skillDir = path.join(skillsSourceDir, entry.name);
      if (!fs.existsSync(path.join(skillDir, "SKILL.md"))) {
        continue;
      }

      if (skills.has(entry.name)) {
        const existing = skills.get(entry.name);
        if (existing !== skillDir) {
          fail(
            `스킬 이름이 중복됩니다: ${entry.name}\n  - ${existing}\n  - ${skillDir}`
          );
        }
        continue;
      }

      skills.set(entry.name, skillDir);
    }
  }

  return skills;
}

// targetDir 안에서 원본이 사라져 깨진 심볼릭 링크를 찾아 제거한다.
function cleanupBrokenSymlinks(targetDir) {
  if (!fs.existsSync(targetDir)) {
    return;
  }

  const entries = fs.readdirSync(targetDir, { withFileTypes: true });

  for (const entry of entries) {
    const entryPath = path.join(targetDir, entry.name);

    if (isSymlink(entryPath) && !fs.existsSync(entryPath)) {
      fs.unlinkSync(entryPath);
      console.log(`정리됨(깨진 링크): ${entry.name} (${targetDir})`);
    }
  }
}

function main() {
  const args = process.argv.slice(2);

  for (const targetDir of targetDirs) {
    cleanupBrokenSymlinks(targetDir);
  }

  const skillsSourceDirs = findSkillsSourceDirs(projectRoot);
  const discoveredSkills = discoverSkills(skillsSourceDirs);

  let skillNames;
  if (args.length > 0) {
    skillNames = args;
    for (const skillName of skillNames) {
      if (!discoveredSkills.has(skillName)) {
        fail(`유효한 스킬을 찾을 수 없습니다: ${skillName}`);
      }
    }
  } else {
    skillNames = Array.from(discoveredSkills.keys());
  }

  if (skillNames.length === 0) {
    console.error(`연결할 스킬이 없습니다: ${projectRoot}`);
    process.exit(0);
  }

  for (const skillName of skillNames) {
    const skillDir = discoveredSkills.get(skillName);

    targetDirs.forEach((targetDir) => {
      const targetLink = path.join(targetDir, skillName);
      const expectedSource = path.relative(targetDir, skillDir);

      if (isSymlink(targetLink)) {
        const actualSource = fs.readlinkSync(targetLink);
        if (actualSource === expectedSource) {
          return;
        }
        fail(`다른 위치를 가리키는 심볼릭 링크가 있습니다: ${targetLink}`);
      }

      if (fs.existsSync(targetLink)) {
        fail(`대상 경로가 이미 존재합니다: ${targetLink}`);
      }
    });
  }

  for (const targetDir of targetDirs) {
    fs.mkdirSync(targetDir, { recursive: true });
  }

  for (const skillName of skillNames) {
    const skillDir = discoveredSkills.get(skillName);

    targetDirs.forEach((targetDir) => {
      const targetLink = path.join(targetDir, skillName);
      const sourcePath = path.relative(targetDir, skillDir);

      if (isSymlink(targetLink)) {
        console.log(`이미 연결됨: ${skillName} (${targetDir})`);
        return;
      }

      fs.symlinkSync(sourcePath, targetLink);
      console.log(`연결됨: ${skillName} (${targetDir})`);
    });
  }
}

main();

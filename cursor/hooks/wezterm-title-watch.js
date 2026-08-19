// WezTerm のペインタイトルを cursor-agent の会話から設定する。
//
// cursor-agent CLI では beforeSubmitPrompt hook が発火しないため、
// Cursor がセッションごとに書き出すチャットファイルを監視して題名を作る。
// どの会話がこのペインのものかは、起動側（.bashrc の __agent_run）が
// `--resume <chatId>` で指定した ID で特定する。cwd 一致では
// 同じディレクトリで複数ペインを開いたときに区別できない。
//   ~/.cursor/chats/<workspace>/<chatId>/meta.json          … 自動生成の題名
//   ~/.cursor/chats/<workspace>/<chatId>/prompt_history.json … 実際に送った文面（新しい順）
//
// 使い方:
//   node wezterm-title-watch.js <paneId> <chatId>
//   node wezterm-title-watch.js --print "最初のプロンプト"
// agent が終わるまで常駐し、題名が変わったら書き直す。
// /clear 後や最初の一言の前は Cursor の自動題名を使わず「未着手」に固定する。

const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);

const home = process.env.USERPROFILE || process.env.HOME;
const cursorHome = path.join(home, ".cursor");
const chatsDir = path.join(cursorHome, "chats");
const logPath = path.join(cursorHome, "logs", "wezterm-pane-title.log");

const POLL_MS = 1500;
const TIMEOUT_MS = 12 * 60 * 60 * 1000;
const MAX_TITLE_CHARS = 16;
const IDLE_TITLE = "未着手";

function log(message, paneId) {
  try {
    fs.mkdirSync(path.dirname(logPath), { recursive: true });
    const tag = paneId ? `watch[${paneId}] ` : "";
    fs.appendFileSync(logPath, `${new Date().toISOString()} ${tag}${message}\n`, "utf8");
  } catch {
    // タイトル設定の失敗で agent の動作を妨げない。
  }
}

function stripRepeat(text, pattern) {
  let previous;
  do {
    previous = text;
    text = text.replace(pattern, "").trim();
  } while (text !== previous);
  return text;
}

function replacePaths(text) {
  // 日本語が続くパスは場所の指定なので捨てる。それ以外は末尾のフォルダ名だけ残す。
  return text.replace(/[A-Za-z]:[\\/][^\u3040-\u9fff]*/g, (matched, offset, source) => {
    const rest = source.slice(offset + matched.length);
    if (/^[\u3040-\u9fff]/.test(rest)) return " ";
    const parts = matched.split(/[\\/]/).filter(Boolean);
    const last = parts[parts.length - 1] || "";
    return last.replace(/["']+$/g, "");
  });
}

function firstChunk(text) {
  const sentence = (text.split(/[。．.!！?？\n]/u)[0] || text).trim();
  const clause = (sentence.split(/ん?だけど|場合|[、,]/u)[0] || sentence).trim();
  if (Array.from(clause).length >= 8 && clause.length < sentence.length) return clause;
  return sentence;
}

const LEADING_FILLER =
  /^(?:ちなみに|今だと|いまだと|いま|今|現在の?|あと[、,]?|いや[、,]?|おっけ[、,]?|おけ[、,]?|では[、,]?|じゃあ[、,]?|じゃ[、,]?|ちょっと|ついでに|そういえば|質問(?:です)?[。．]?|ここに|この)+/u;

const TRAILING_REQUEST =
  /(?:を)?(?:教えて(?:ください|下さい)?|お願い(?:します|いたします)?|してください|して下さい|して下し[亜あ]?|してほしい|して欲しい|やってください|対応してください|確認して(?:ください|下さい)?|まとめて(?:ください|下さい)?|聞きます|してくれ|してくダサい|して)[。．.!！?？]*$/u;

const TRAILING_HEDGE =
  /(?:かも(?:しれない)?|かな|気がする|と思う|ですか|でしょうか|だよね|ってことだよね|わかりますか|わかりません|あるか|ありますか|余地あるか)[。．.!！?？]*$/u;

const TRAILING_EVAL =
  /(?:が|は)?(?:ちょっと)?(?:適当|おかしい|足りない|正しく動作しません|動きません|壊れ(?:てる|ている)|決めれない|決められない).*$/u;

const TRAILING_QUESTION =
  /(?:はいくつ.*|はどんな.*|どんな事.*|ってあるの.*|使える|できる|出来る|したい)$/u;

const TRAILING_POLITE =
  /(?:しています|します(?:が)?|ようです|です(?:が)?|ます(?:が)?|する(?:タスク)?|することは|すること|のタスク|したいです)$/u;

const TRAILING_PARTICLE = /(?:について|を|に|で|と|へ|も|が)+$/u;

function extractFocus(text) {
  let match;

  text = text.replace(/についての/gu, "の");

  // 「XによるY」は Y が作業内容。
  match = text.match(/による(.{2,16})$/u);
  if (match) return match[1];

  match = text.match(/における(.{2,16})$/u);
  if (match) return match[1];

  // 「Xについて」で終わる／直後が本題でないときは X が題名。
  match = text.match(/^(.{2,16}?)について(?:は|を|が|も|いま|今)?(.*)$/u);
  if (match) {
    const topic = match[1].trim();
    const rest = (match[2] || "").trim();
    if (!rest || Array.from(rest).length <= 2) return topic;
    if (Array.from(topic).length >= 4) return topic;
  }

  return text;
}

function longestFittingSuffix(text, max) {
  const particles = ["について", "による", "における", "での", "って", "から", "まで", "を", "に", "の", "で", "が", "は", "と", "へ", "も"];
  let best = "";
  for (const particle of particles) {
    let from = 0;
    while (from < text.length) {
      const index = text.indexOf(particle, from);
      if (index < 0) break;
      const suffix = text.slice(index + particle.length).trim();
      const length = Array.from(suffix).length;
      if (length >= 4 && length <= max && length > Array.from(best).length) {
        best = suffix;
      }
      from = index + 1;
    }
  }
  return best;
}

function clip(text, max) {
  const chars = Array.from(text);
  if (chars.length <= max) return text;

  // 長文は「主語が〜」の主語側の方が、末尾の感想より作業内容になる。
  const subject = text.match(/^(.{4,16}?)[がは]/u);
  if (subject) return subject[1];

  const suffix = longestFittingSuffix(text, max);
  if (suffix) return suffix;

  return `${chars.slice(0, max - 1).join("")}…`;
}

function summarize(prompt) {
  let text = String(prompt || "")
    .replace(/<[^>]+>/g, " ")
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (!text) return "";

  text = replacePaths(text);
  text = firstChunk(text);
  text = text.replace(/おそらく/gu, "");
  text = stripRepeat(text, LEADING_FILLER);
  text = stripRepeat(text, TRAILING_EVAL);
  text = stripRepeat(text, TRAILING_REQUEST);
  text = stripRepeat(text, TRAILING_HEDGE);
  text = stripRepeat(text, TRAILING_QUESTION);
  text = stripRepeat(text, TRAILING_POLITE);
  text = stripRepeat(text, /[。．.!！?？、,]+$/u);
  text = extractFocus(text);
  text = stripRepeat(text, TRAILING_PARTICLE);
  text = text.replace(/\s+/g, " ").trim();

  if (!text) return "";
  return clip(text, MAX_TITLE_CHARS);
}

function findChatDir(chatId) {
  let workspaces = [];
  try {
    workspaces = fs.readdirSync(chatsDir);
  } catch {
    return null;
  }

  for (const workspace of workspaces) {
    const dir = path.join(chatsDir, workspace, chatId);
    try {
      if (fs.statSync(dir).isDirectory()) return dir;
    } catch {
      // まだ作られていないだけなので次回のポーリングで拾う。
    }
  }
  return null;
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    // 書き込み途中で壊れた JSON を読むことがある。次回のポーリングに任せる。
    return null;
  }
}

// prompt_history.json は新しい順で、/clear をまたいで同じファイルに積み上がる。
// いま続いている会話は先頭から直近の /clear までなので、その末尾＝最初の一言を使う。
function firstPromptFromHistory(history) {
  if (!Array.isArray(history)) return null;

  const entries = [];
  for (const raw of history) {
    const text = String(raw || "").trim();
    if (text === "/clear" || text === "clear") break;
    if (text.startsWith("/")) continue; // /model などのコマンドは題名にしない
    if (text) entries.push(text);
  }
  return entries.length > 0 ? entries[entries.length - 1] : null;
}

function currentFirstPrompt(dir) {
  return firstPromptFromHistory(readJson(path.join(dir, "prompt_history.json")));
}

function resolveTitle(dir) {
  const prompt = currentFirstPrompt(dir);
  if (prompt) return summarize(prompt);
  // /clear 直後や未入力は meta.json の古い自動題名（英語ラベル）に戻さない。
  return IDLE_TITLE;
}

function writeTitle(titleFile, title) {
  fs.mkdirSync(path.dirname(titleFile), { recursive: true });
  const temporary = `${titleFile}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${title}\n`, "utf8");
  fs.renameSync(temporary, titleFile);
}

function watch(paneId, chatId) {
  const titleFile = path.join(cursorHome, "pane-titles", `${paneId}.txt`);
  const startedAt = Date.now();
  let lastTitle = "";

  function tick() {
    if (Date.now() - startedAt > TIMEOUT_MS) {
      log("timeout", paneId);
      process.exit(0);
    }

    try {
      const dir = findChatDir(chatId);
      const title = dir ? resolveTitle(dir) : IDLE_TITLE;
      if (title && title !== lastTitle) {
        writeTitle(titleFile, title);
        lastTitle = title;
        log(`set title=${JSON.stringify(title)} chat=${chatId}`, paneId);
      }
    } catch (error) {
      log(`scan error: ${error.message}`, paneId);
    }

    setTimeout(tick, POLL_MS);
  }

  tick();
}

const SELF_TEST = [
  ["weztermのagentによるタイトル設定がちょっと適当かも", "タイトル設定"],
  ["今だとwezterm起動時にフォルダ選択しますが、なんのためのフォルダ選択かわかりません。この文字列って決めれらないですか？", "フォルダ選択"],
  ["weztermのluaをリファクタリングする余地あるか確認して", "luaをリファクタリング"],
  ["lazyworktreeについて", "lazyworktree"],
  ["ADB負荷について聞きます。現状わかっていることわからないこと今後確認する必要があることをまとめてください。", "ADB負荷"],
  ["タスクについての現状を教えて", "タスクの現状"],
  ["ADBの監査タスクについていまわっていることこれからやらないといけないことを教えて", "ADBの監査タスク"],
  ["hooks使える？", "hooks"],
  ["oci-mcpを有効化したいです。このプロジェクト限定ですが、", "oci-mcpを有効化"],
  ["cursorについて教えて", "cursor"],
  ["wiztermについて教えて", "wizterm"],
  ["weztermのタイトルが正しく動作しません。weztermの再起動が必要ですか？", "weztermのタイトル"],
  ["neovimのカスタマイズはどんな事が出来る？", "neovimのカスタマイズ"],
  ["C:\\99_obsidian\\default vault\\10 Knowledgeここに現在のweztermの構成をまとめてください。ai活用についてフォーカスしたものが良い", "weztermの構成"],
  ["update_schema修正のタスクですが、同僚にフォルダ名の変更依頼をします。", "update_schema修正"],
  ["こんにちは", "こんにちは"],
  ["lazyworktreeのeditorが開けないんだけどnvimを入れないとダメ？", "editorが開けない"],
  ["hooksはおそらく長いプロンプトに対応できてないようです。直して下し亜。", "hooks"],
];

const IDLE_TITLE_TEST = [
  [["/clear", "古い作業の最初の一言"], null, IDLE_TITLE],
  [["/model opus", "/clear", "古い作業"], null, IDLE_TITLE],
  [[], null, IDLE_TITLE],
  [["新しい作業を始める", "/clear", "古い作業"], "新しい作業を始める", "新しい作業を始める"],
];

function runSelfTest() {
  let failed = 0;
  for (const [input, expected] of SELF_TEST) {
    const actual = summarize(input);
    const mark = actual === expected ? "ok" : "NG";
    if (actual !== expected) failed += 1;
    console.log(`${mark}\n  in:  ${input.slice(0, 60)}\n  out: ${actual}\n  exp: ${expected}`);
  }
  for (const [history, expectedPrompt, expectedTitle] of IDLE_TITLE_TEST) {
    const prompt = firstPromptFromHistory(history);
    const title = prompt ? summarize(prompt) : IDLE_TITLE;
    const ok = prompt === expectedPrompt && title === expectedTitle;
    if (!ok) failed += 1;
    console.log(
      `${ok ? "ok" : "NG"}\n  hist: ${JSON.stringify(history)}\n  prompt: ${prompt}\n  title: ${title}\n  exp: ${expectedPrompt} / ${expectedTitle}`,
    );
  }
  process.exit(failed === 0 ? 0 : 1);
}

if (require.main === module) {
  if (args[0] === "--print") {
    process.stdout.write(`${summarize(args.slice(1).join(" "))}\n`);
    process.exit(0);
  }

  if (args[0] === "--self-test") {
    runSelfTest();
  }

  const [paneId, chatId] = args;
  if (!paneId || !chatId) {
    log("missing arguments");
    process.exit(0);
  }

  watch(paneId, chatId);
}

module.exports = { summarize, clip, resolveTitle, currentFirstPrompt, firstPromptFromHistory, IDLE_TITLE };

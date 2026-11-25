/// PHP 运行时小库的源码（数据集合：存在 `lc_data.json` 文件里、加文件锁；生成的工程里的 `lc_data.php`）。每份工程都一样。
///
/// **没有在真机器上实际运行过**（本机没有 php）：只做了结构检查（test/backend_codegen_langs_test.dart）。凭记忆写的 PHP 函数清单见 docs/api-notes.md。
/// 值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库。
library;

const String kPhpRuntimeDataSource = r'''
<?php
// LopiCode 后端运行时小库（PHP）：数据集合。每份生成的工程都一样，不用改。
// 注意：这份 PHP 代码还没有在真机器上实际运行过。

const LC_DATA_FILE = __DIR__ . '/lc_data.json'; // 数据集合存在这个文件里

// —— 数据集合 ——
// PHP 每个请求都是从头跑一遍，内存里留不住东西，所以集合存在 lc_data.json 里：
// 一次请求里第一次用到集合时打开文件、加上独占锁、读进来；请求结束时有改动就写回去，再放开锁。

final class LcDb
{
    public static $handle = null;
    public static $data = array(); // 集合名 → array('next' => 下一个 id, 'rows' => 记录的列表)
    public static $dirty = false;
}

function lc_db_open()
{
    if (LcDb::$handle !== null) {
        return;
    }
    $h = fopen(LC_DATA_FILE, 'c+');
    if ($h === false || !flock($h, LOCK_EX)) {
        throw new RuntimeException('打不开数据文件 lc_data.json');
    }
    LcDb::$handle = $h;
    LcDb::$data = array();
    LcDb::$dirty = false;
    $saved = lc_parse_json((string) stream_get_contents($h));
    if (!($saved instanceof LcObj)) {
        return; // 空文件，或者内容坏了：当成没有数据
    }
    foreach (lc_keys($saved) as $name) {
        $c = $saved->f[$name];
        $rows = array();
        foreach (lc_items(lc_field($c, 'rows')) as $row) {
            if ($row instanceof LcObj) {
                $rows[] = $row;
            }
        }
        $next = lc_to_num(lc_field($c, 'next'));
        LcDb::$data[$name] = array('next' => $next >= 1 ? $next : 1.0, 'rows' => $rows);
    }
}

// 请求结束时调：有改动就写回文件，放开锁。
function lc_db_close()
{
    $h = LcDb::$handle;
    if ($h === null) {
        return;
    }
    LcDb::$handle = null;
    if (LcDb::$dirty) {
        $all = new LcObj();
        foreach (LcDb::$data as $name => $c) {
            $all->f[(string) $name] = lc_obj('next', $c['next'], 'rows', $c['rows']);
        }
        rewind($h);
        ftruncate($h, 0);
        fwrite($h, lc_to_json($all, true));
        fflush($h);
    }
    flock($h, LOCK_UN);
    fclose($h);
}

// 声明一个集合（别的语言的小库在这里建表；PHP 版第一次用到时才建，这里什么都不用做）。
function lc_collection($name)
{
}

// 确保这个集合在，返回它的名字（当数组的键用）。
function lc_db_use($name)
{
    lc_db_open();
    $name = (string) $name;
    if (!array_key_exists($name, LcDb::$data)) {
        LcDb::$data[$name] = array('next' => 1.0, 'rows' => array());
    }
    return $name;
}

// 找 id 是 $id 的那条在第几个；找不到返回 -1。
function lc_db_index($name, $id)
{
    $want = lc_to_num($id);
    foreach (LcDb::$data[$name]['rows'] as $i => $row) {
        $have = lc_field($row, 'id');
        if ((is_float($have) || is_int($have)) && (float) $have === $want) {
            return $i;
        }
    }
    return -1;
}

function lc_dbAll($name)
{
    $name = lc_db_use($name);
    return new LcList(LcDb::$data[$name]['rows']);
}

function lc_dbCount($name)
{
    $name = lc_db_use($name);
    return (float) count(LcDb::$data[$name]['rows']);
}

function lc_dbGet($name, $id)
{
    $name = lc_db_use($name);
    $i = lc_db_index($name, $id);
    return $i < 0 ? null : LcDb::$data[$name]['rows'][$i];
}

function lc_dbFind($name, $key, $value)
{
    $name = lc_db_use($name);
    $out = array();
    foreach (LcDb::$data[$name]['rows'] as $row) {
        if (lc_eq(lc_field($row, $key), $value)) {
            $out[] = $row;
        }
    }
    return new LcList($out);
}

function lc_dbInsert($name, $value)
{
    $name = lc_db_use($name);
    $row = new LcObj();
    if ($value instanceof LcObj) {
        $row->f = $value->f;
    }
    $row->f['id'] = LcDb::$data[$name]['next'];
    LcDb::$data[$name]['next'] += 1.0;
    LcDb::$data[$name]['rows'][] = $row;
    LcDb::$dirty = true;
    return $row;
}

// 改的是一份新的记录（之前读出来的那份不会跟着变）。
function lc_dbUpdate($name, $id, $value)
{
    $name = lc_db_use($name);
    $i = lc_db_index($name, $id);
    if ($i < 0) {
        return null;
    }
    $old = LcDb::$data[$name]['rows'][$i];
    if (!($value instanceof LcObj)) {
        return $old;
    }
    $row = new LcObj();
    $row->f = $old->f;
    foreach ($value->f as $k => $v) {
        $row->f[$k] = $v;
    }
    $row->f['id'] = $old->f['id'];
    LcDb::$data[$name]['rows'][$i] = $row;
    LcDb::$dirty = true;
    return $row;
}

function lc_dbDelete($name, $id)
{
    $name = lc_db_use($name);
    $i = lc_db_index($name, $id);
    if ($i < 0) {
        return false;
    }
    array_splice(LcDb::$data[$name]['rows'], $i, 1);
    LcDb::$dirty = true;
    return true;
}
''';

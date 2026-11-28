part of 'builder_screen.dart';

/// 搭建页里“打开别的面板 / 页面、导出、删组件、改尺寸”这些动作（从 builder_screen.dart 拆出来的，行为不变）。
extension _BuilderActions on _BuilderScreenState {
  Future<void> _exportDart() async {
    final code = exportDart(_doc!);
    const path = 'export/page.dart';
    try {
      final file = File(widget.session.guard.resolve(path));
      await file.parent.create(recursive: true);
      await file.writeAsString(code);
      widget.session.filesChanged();
    } on FileSystemException catch (e) {
      if (mounted) showEditorHint(context, '写入 $path 失败：${describeSaveError(e)}');
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CodeSheetBody(title: 'Flutter 代码', note: '已保存到项目的 $path', code: code, language: 'dart'),
    );
  }

  Future<void> _renamePage() async {
    final name = await promptDialog(context, title: '页面标题', initial: _doc!.title, confirmLabel: '保存');
    if (name == null || name.trim().isEmpty) return;
    _apply((d) => d.title = name.trim());
  }

  /// 换到另一页去编辑。不算修改：不记撤销、不存盘（“在看哪一页”不进页面文件）。
  void _openPage(String id) {
    final doc = _doc!;
    if (doc.page.id == id || doc.pageById(id) == null) return;
    if (multiOn) multiExit();
    _mut(() {
      doc.openPage(id);
      _selected = null;
    });
  }

  Future<void> _openPages() async {
    _bench.currentState?.closeInspector();
    await showPagesSheet(context, doc: () => _doc!, onEdit: _apply, onOpen: _openPage);
    _refresh();
  }

  /// 拖柄松手：把宽 / 高写进组件自己的样式。整次拖动只走这一次统一入口，所以只记一条撤销。
  /// 画布切到了平板 / 桌面时，写的是那一档的差别（手机的样子不动）。
  void _resize(String id, int? width, int? height) => _apply((d) {
    final n = d.find(id);
    if (n == null) return;
    void set(Map<String, String> map) {
      final style = LcStyle(map);
      if (width != null) style.setLength('width', LcLength.px(width.toDouble()));
      if (height != null) style.setLength('height', LcLength.px(height.toDouble()));
    }

    final bp = _bp;
    bp == null ? set(n.style) : lcEditAtBp(n, bp, set);
  });

  /// 删除组件。积木逻辑里还有地方在用它（或它里面的组件）时先问一句；
  /// 清逻辑和删组件放在同一次修改里，撤销一次就能全部恢复。
  Future<void> _delete(LcNode node) async {
    final ids = <String>[];
    void walk(LcNode n) {
      ids.add(n.id);
      n.children.forEach(walk);
    }

    walk(node);
    final refs = ids.fold<int>(0, (sum, id) => sum + _doc!.logic.nodeRefCount(id));
    if (refs > 0) {
      final ok = await confirmDialog(context, title: '删除${node.spec.label}', message: '有 $refs 处积木逻辑在用这个组件，删除会一并清掉。', confirmLabel: '删除', danger: true);
      if (!ok || !mounted) return;
    }
    _apply((d) {
      if (d.find(node.id) == null) return;
      for (final id in ids) {
        d.logic.removeNodeRefs(id);
      }
      d.remove(node.id);
    });
    _mut(() => _selected = null);
  }

  Future<void> _openLogic([String? nodeId]) async {
    // 新的页面逻辑（或者这一页还没有任何逻辑）走新的逻辑页；有旧处理的页面照旧，顶栏多一颗“升级到新的页面逻辑…”。
    final doc = _doc!;
    final fresh = doc.logic.front != null || doc.logic.handlers.isEmpty;
    final upgrade = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        // 逻辑页是另开的一页：也接上背景（跟“其它页面”开关走），不然“透出背景 › 积木画布”在这页不起作用
        builder: (route) => AppBackdrop(
          area: BackdropArea.pages,
          builder: (_, _) => fresh
              ? LogicFrontScreen(doc: _doc!, onEdit: _apply, session: widget.session, initialNodeId: nodeId)
              : LogicScreen(doc: _doc!, onEdit: _apply, initialNodeId: nodeId, history: _history, onRestore: _restore, onUpgrade: () => Navigator.of(route).pop(true)),
        ),
      ),
    );
    _refresh();
    if (upgrade != true || !mounted) return;
    // 点了“升级”：问清楚；升了打开新的逻辑页，没升回到旧的逻辑页。
    await showLcFrontUpgrade(context, _doc!, _apply);
    if (mounted) await _openLogic(nodeId);
  }

  Future<void> _openComponents() async {
    final id = await showComponentSheet(context, doc: _doc!, onEdit: _apply, selectedNodeId: _selected, recents: _recents, images: _images);
    if (!mounted) return;
    if (id != null && _doc?.find(id) != null) _selected = id;
    _refresh();
  }

  /// 选中操作条里和自定义组件有关的三项：存成组件、编辑组件（改它的内容）、拆开成普通控件。
  Future<void> _componentAction(String action, LcNode node) async {
    final doc = _doc!;
    switch (action) {
      case 'save':
        final id = await saveAsComponentFlow(context, doc: doc, onEdit: _apply, nodeId: node.id);
        if (id != null) _selected = id;
      case 'edit':
        final ref = node.strProp('ref') ?? '';
        final def = doc.component(ref);
        final from = def == null ? null : compLibOf(def);
        if (from == null) {
          await showComponentEditor(context, doc: doc, onEdit: _apply, componentId: ref, recents: _recents, images: _images);
        } else if (await confirmDialog(context, title: '这是库里的组件', message: '「${def!.name}」来自组件库「${from.name}」，不能直接改。可以复制一份成项目自己的组件，这一处换成副本，再去改。', confirmLabel: '复制一份来改')) {
          if (!mounted) return;
          String? made;
          _apply((d) {
            made = compLibFork(d, ref);
            if (made != null) d.find(node.id)?.props['ref'] = made;
          });
          if (made != null) await showComponentEditor(context, doc: _doc!, onEdit: _apply, componentId: made!, recents: _recents, images: _images);
        }
      case 'toLib':
        await _openLibs(pick: node.strProp('ref'));
      case 'detach':
        await detachInstanceFlow(context, doc: doc, onEdit: _apply, instanceId: node.id);
    }
    _refresh();
  }

  Future<void> _openLibs({String? pick}) async {
    final def = pick == null ? null : _doc!.component(pick);
    if (def != null && compLibOf(def) != null) {
      showEditorHint(context, '它本来就是库「${compLibOf(def)!.name}」里的组件');
      return;
    }
    await showCompLibSheet(context, doc: () => _doc!, onEdit: _apply, images: _images, pickComponent: pick);
    if (mounted) _refresh();
  }

  Future<void> _openFrameworkExport() async {
    await showFrameworkExport(context, doc: _doc!, session: widget.session);
    _refresh();
  }

  /// 去预览：先把没存的存掉（预览读的是导出的网页文件）。
  Future<void> _preview() async {
    await _saver.flush();
    if (!mounted) return;
    final shell = ShellScope.maybeOf(context);
    if (shell != null) {
      shell.go(ShellDest.preview);
    } else {
      Navigator.pop(context, 'preview');
    }
  }

  Future<void> _openTheme() async {
    await showThemeVarsScreen(context, doc: () => _doc!, onEdit: _apply);
    if (mounted) _refresh();
  }

  Future<void> _openState() async {
    await showStateScreen(context, doc: () => _doc!, onEdit: _apply);
    if (mounted) _refresh();
  }

  void _openView() {
    final canvas = _bench.currentState?.canvas;
    if (canvas == null) return;
    unawaited(
      showCanvasViewSheet(
        context,
        canvas: canvas,
        presetWidth: () => _presetWidth,
        // 在这里挑了屏宽档＝回到手机（默认）那一档看：平板 / 桌面的宽度是固定的。
        onPresetWidth: (v) => _mut(() {
          _presetWidth = v;
          _bp = null;
        }),
        showBoxModel: () => _showBoxModel,
        onShowBoxModel: (v) => _mut(() => _showBoxModel = v),
      ),
    );
  }

  void _onMenu(String v) {
    switch (v) {
      case 'view':
        _openView();
      case 'theme':
        unawaited(_openTheme());
      case 'state':
        unawaited(_openState());
      case 'dart':
        unawaited(_exportDart());
      case 'framework':
        unawaited(_openFrameworkExport());
      case 'logic':
        unawaited(_openLogic());
      case 'components':
        unawaited(_openComponents());
      case 'libs':
        unawaited(_openLibs());
      case 'pages':
        unawaited(_openPages());
      case 'title':
        unawaited(_renamePage());
    }
  }
}

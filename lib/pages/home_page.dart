import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/swf_info.dart';
import 'player_page.dart';

const _ruffleLogoPngBase64 =
    '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';

final Uint8List _ruffleLogoPngBytes = base64Decode(_ruffleLogoPngBase64);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  /// 创建主页状态对象。
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isPicking = false;
  final TextEditingController _urlController = TextEditingController();

  @override
  /// 释放资源。
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 选择本地 SWF 文件，并跳转到播放器页加载显示。
  Future<void> _pickAndOpenPlayer() async {
    try {
      if (_isPicking) return;
      setState(() => _isPicking = true);
      final FilePickerResult? result;
      if (Platform.isIOS) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: true,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['swf', 'SWF'],
          withData: true,
        );
      }
      if (result == null) {
        return;
      }
      final file = result.files.single;
      final nameLower = file.name.toLowerCase();
      final pathLower = file.path?.toLowerCase();
      final isSwf =
          nameLower.endsWith('.swf') || (pathLower?.endsWith('.swf') ?? false);
      if (!isSwf) {
        throw StateError('请选择 .swf 文件');
      }
      final bytes =
          file.bytes ??
          (file.path == null
              ? (throw StateError('FilePicker 未返回 bytes 或 path'))
              : await File(file.path!).readAsBytes());
      final url = file.path == null
          ? 'file:///picked.swf'
          : Uri.file(file.path!).toString();
      final source = SwfSource(
        name: file.name,
        url: url,
        bytes: bytes,
        filePath: file.path,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (context) => PlayerPage(source: source),
        ),
      );
    } catch (e) {
      unawaited(_showErrorDialog('加载失败', e.toString()));
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  /// 从链接加载 SWF（支持 https/http/file），并跳转到播放器页。
  Future<void> _openFromUrl() async {
    try {
      if (_isPicking) return;
      final raw = _urlController.text.trim();
      if (raw.isEmpty) {
        await _showErrorDialog('加载失败', '请输入链接');
        return;
      }
      setState(() => _isPicking = true);
      final uri = Uri.parse(raw);
      final bytes = await _loadBytesFromUri(uri);
      final name = uri.pathSegments.isEmpty
          ? 'link.swf'
          : uri.pathSegments.last;
      final source = SwfSource(
        name: name.isEmpty ? 'link.swf' : name,
        url: uri.toString(),
        bytes: bytes,
        filePath: null,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (context) => PlayerPage(source: source),
        ),
      );
    } catch (e) {
      unawaited(_showErrorDialog('加载失败', e.toString()));
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  /// 从 Uri 读取二进制数据（https/http/file）。
  Future<Uint8List> _loadBytesFromUri(Uri uri) async {
    if (uri.scheme == 'file') {
      return File.fromUri(uri).readAsBytes();
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        req.headers.set(HttpHeaders.userAgentHeader, 'flutter_ruffle');
        final resp = await req.close();
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw StateError('HTTP ${resp.statusCode}');
        }
        final chunks = <int>[];
        await for (final c in resp) {
          chunks.addAll(c);
        }
        return Uint8List.fromList(chunks);
      } finally {
        client.close(force: true);
      }
    }
    throw StateError('不支持的链接类型: ${uri.scheme}');
  }

  /// 显示错误弹窗。
  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              isDefaultAction: true,
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  /// 构建主页：只负责选择文件并跳转播放器页。
  Widget build(BuildContext context) {
    final bg = const Color(0xFFFAF6EF);
    final primary = const Color(0xFF7A4D0A);
    final primaryFg = const Color(0xFFFAF6EF);
    final fieldBg = const Color(0xFFFFFFFF);
    final border = const Color(0xFFDBCBB3);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Material(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: 32),
                      Center(
                        child: SizedBox(
                          width: 140,
                          height: 160,
                          child: Image.memory(
                            _ruffleLogoPngBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: fieldBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: border),
                            ),
                            child: CupertinoTextField(
                              controller: _urlController,
                              enabled: !_isPicking,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.go,
                              placeholder: 'https://example.com/game.swf',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: null,
                              onSubmitted: (_) => unawaited(_openFromUrl()),
                              style: const TextStyle(
                                color: CupertinoColors.black,
                              ),
                              placeholderStyle: TextStyle(
                                color: CupertinoColors.black.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              color: primary,
                              borderRadius: BorderRadius.circular(999),
                              onPressed: _isPicking ? null : _openFromUrl,
                              child: _isPicking
                                  ? const CupertinoActivityIndicator()
                                  : Text(
                                      '打开链接',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: primaryFg,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '或',
                            style: TextStyle(
                              color: CupertinoColors.black.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              color: CupertinoColors.white.withValues(
                                alpha: 0.60,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              onPressed: _isPicking ? null : _pickAndOpenPlayer,
                              child: Text(
                                '选择本地 SWF 文件',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

from pathlib import Path
p = Path(r'C:\Users\user\Documents\stock-helper-flutter\lib\screens\holdings_screen.dart')
t = p.read_text(encoding='utf-8')
old = '''      final drafts = await _ocr.pickAndParse(source);
      if (!mounted) return;
      if (drafts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未辨識到可匯入的持倉列')),
        );
        return;
      }
      await widget.names.ensureLoaded();
      for (final d in drafts) {
        if (d.name.trim().isEmpty) {
          try {
            final t = normalizeTicker(d.code);
            d.name = widget.names.resolveName(t);
          } catch (_) {}
        }
      }
      final confirmed = await _showOcrConfirmDialog(drafts);'''
new = '''      await widget.names.ensureLoaded();
      final drafts = await _ocr.pickAndParse(source, names: widget.names);
      if (!mounted) return;
      if (drafts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未辨識到可匯入的持倉列')),
        );
        return;
      }
      // Ensure name<->code enrichment even if service path skipped it.
      enrichDraftsWithNames(drafts, widget.names);
      final confirmed = await _showOcrConfirmDialog(drafts);'''
if old not in t:
    raise SystemExit('block not found')
p.write_text(t.replace(old, new, 1), encoding='utf-8')
print('holdings_screen enrich updated')

# Also improve dialog: show hint when code empty
t2 = p.read_text(encoding='utf-8')
old2 = '''                                  TextField(
                                    controller: codeCtrls[i],
                                    decoration: const InputDecoration(
                                      labelText: '代號',
                                      isDense: true,
                                    ),
                                    onChanged: (v) => d.code = v.trim(),
                                  ),'''
new2 = '''                                  TextField(
                                    controller: codeCtrls[i],
                                    decoration: InputDecoration(
                                      labelText: '代號',
                                      isDense: true,
                                      hintText: d.code.isEmpty ? '可由股名自動對應，可手動改' : null,
                                    ),
                                    onChanged: (v) {
                                      d.code = v.trim();
                                      setLocal(() {});
                                    },
                                  ),'''
if old2 not in t2:
    raise SystemExit('code field block not found')
p.write_text(t2.replace(old2, new2, 1), encoding='utf-8')
print('dialog code hint updated')
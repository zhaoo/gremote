import 'package:flutter/material.dart';

class PrecisionField {
  const PrecisionField(this.label, this.value, this.min, this.max,
      {this.key, this.enabled = true});
  final String label;
  final double value, min, max;
  final Key? key;
  final bool enabled;
}

Future<List<double>?> showPrecisionDialog(BuildContext context,
        {required String title, required List<PrecisionField> fields}) =>
    showDialog<List<double>>(
        context: context,
        builder: (_) => _PrecisionDialog(title: title, fields: fields));

class _PrecisionDialog extends StatefulWidget {
  const _PrecisionDialog({required this.title, required this.fields});
  final String title;
  final List<PrecisionField> fields;
  @override
  State<_PrecisionDialog> createState() => _PrecisionDialogState();
}

class _PrecisionDialogState extends State<_PrecisionDialog> {
  final _form = GlobalKey<FormState>();
  late final _controllers = [
    for (final f in widget.fields)
      TextEditingController(
          text: f.value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), ''))
  ];
  double? _number(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));
  void _apply() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, [for (final c in _controllers) _number(c.text)!]);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 280,
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < widget.fields.length; i++)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextFormField(
                              key: widget.fields[i].key,
                              controller: _controllers[i],
                              enabled: widget.fields[i].enabled,
                              autofocus: i == 0 && widget.fields[i].enabled,
                              onTap: () => _controllers[i].selection =
                                  TextSelection(
                                      baseOffset: 0,
                                      extentOffset:
                                          _controllers[i].text.length),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              textInputAction: i == widget.fields.length - 1
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              onFieldSubmitted: (_) {
                                if (i == widget.fields.length - 1) _apply();
                              },
                              decoration: InputDecoration(
                                  labelText: widget.fields[i].label,
                                  helperText:
                                      '${widget.fields[i].min.toStringAsFixed(0)} – ${widget.fields[i].max.toStringAsFixed(0)}'),
                              validator: (text) {
                                final n = _number(text ?? '');
                                return n == null ||
                                        !n.isFinite ||
                                        n < widget.fields[i].min ||
                                        n > widget.fields[i].max
                                    ? '请输入范围内的数值'
                                    : null;
                              })),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(onPressed: _apply, child: const Text('应用'))
          ]);
}

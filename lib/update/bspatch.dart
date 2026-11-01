// bspatch (formato BSDIFF40 de bsdiff 4.x: cabecera de 32 bytes + control, diff y extra en bzip2).
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class BsPatchException implements Exception {
  final String message;
  BsPatchException(this.message);
  @override
  String toString() => 'bspatch: $message';
}

int _offt(Uint8List b, int o) {
  var y = b[o + 7] & 0x7f;
  for (var i = 6; i >= 0; i--) {
    y = y * 256 + b[o + i];
  }
  return (b[o + 7] & 0x80) != 0 ? -y : y;
}

class _Parsed {
  final int newSize;
  final Uint8List ctrl, diff, extra;
  _Parsed(this.newSize, this.ctrl, this.diff, this.extra);
}

_Parsed _parse(Uint8List patch) {
  if (patch.length < 32 || String.fromCharCodes(patch.sublist(0, 8)) != 'BSDIFF40') {
    throw BsPatchException('cabecera inválida');
  }
  final cLen = _offt(patch, 8), dLen = _offt(patch, 16), newSize = _offt(patch, 24);
  if (cLen < 0 || dLen < 0 || newSize < 0 || 32 + cLen + dLen > patch.length) throw BsPatchException('tamaños inválidos');
  Uint8List bz(int from, int len) => Uint8List.fromList(BZip2Decoder().decodeBytes(Uint8List.sublistView(patch, from, from + len)));
  return _Parsed(newSize, bz(32, cLen), bz(32 + cLen, dLen), bz(32 + cLen + dLen, patch.length - 32 - cLen - dLen));
}

/// Aplica el parche en memoria (tests y archivos pequeños).
Uint8List bspatchBytes(Uint8List old, Uint8List patch) {
  final out = BytesBuilder(copy: false);
  _apply(_parse(patch), old.length, (pos, len) => Uint8List.sublistView(old, pos, pos + len), out.add);
  return out.takeBytes();
}

/// Aplica el parche sin cargar el APK viejo entero en memoria; escribe el nuevo en [outPath].
Future<void> bspatchFile(String oldPath, String patchPath, String outPath) async {
  final p = _parse(await File(patchPath).readAsBytes());
  final raf = await File(oldPath).open();
  final sink = File(outPath).openWrite();
  try {
    final oldLen = await raf.length();
    _apply(p, oldLen, (pos, len) {
      raf.setPositionSync(pos);
      return raf.readSync(len);
    }, sink.add);
  } finally {
    await raf.close();
    await sink.close();
  }
}

void _apply(_Parsed p, int oldLen, Uint8List Function(int pos, int len) readOld, void Function(Uint8List) emit) {
  var newPos = 0, oldPos = 0, c = 0, d = 0, e = 0;
  while (newPos < p.newSize) {
    if (c + 24 > p.ctrl.length) throw BsPatchException('control corto');
    final add = _offt(p.ctrl, c), copy = _offt(p.ctrl, c + 8), seek = _offt(p.ctrl, c + 16);
    c += 24;
    if (add < 0 || copy < 0 || newPos + add > p.newSize || d + add > p.diff.length) throw BsPatchException('bloque diff');
    final buf = Uint8List(add);
    buf.setRange(0, add, p.diff, d);
    // Sumar el viejo solo donde existe (igual que bspatch.c).
    final lo = oldPos < 0 ? -oldPos : 0;
    final hi = (oldLen - oldPos) < add ? oldLen - oldPos : add;
    if (hi > lo) {
      final o = readOld(oldPos + lo, hi - lo);
      for (var i = lo; i < hi; i++) {
        buf[i] = (buf[i] + o[i - lo]) & 0xff;
      }
    }
    emit(buf);
    d += add;
    newPos += add;
    oldPos += add;
    if (newPos + copy > p.newSize || e + copy > p.extra.length) throw BsPatchException('bloque extra');
    emit(Uint8List.sublistView(p.extra, e, e + copy));
    e += copy;
    newPos += copy;
    oldPos += seek;
  }
}

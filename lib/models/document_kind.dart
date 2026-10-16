enum DocumentKind { image, pdf }

DocumentKind? documentKindFromName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  switch (name.substring(dot + 1).toLowerCase()) {
    case 'pdf':
      return DocumentKind.pdf;
    case 'jpg':
    case 'jpeg':
    case 'png':
      return DocumentKind.image;
    default:
      return null;
  }
}

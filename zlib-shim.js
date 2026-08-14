module.exports = {
  constants: {},
  createDeflateRaw() { throw new Error('zlib compression is unavailable on this client'); },
  createInflateRaw() { throw new Error('zlib compression is unavailable on this client'); },
  deflateRaw() { throw new Error('zlib compression is unavailable on this client'); },
  inflateRaw() { throw new Error('zlib compression is unavailable on this client'); },
};

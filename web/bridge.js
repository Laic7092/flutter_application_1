class BookBridge {
  constructor() {
    this.callbacks = {};
    this.callbackId = 0;
    window.bookBridge = this;
    this._setupMock();
  }

  _setupMock() {
    this._mockDownloadBook = (url, filename) => {
      return Promise.resolve({
        success: true,
        filename: filename || 'test_book.epub',
        size: 1024 * 1024,
        base64: 'dGVzdCBib29r',
      });
    };

    this._mockGetBookList = () => {
      return Promise.resolve({
        success: true,
        books: [
          { name: 'The Great Gatsby.epub', size: 1024 * 512, path: '/books/gatsby.epub' },
          { name: '1984.epub', size: 1024 * 768, path: '/books/1984.epub' },
        ],
      });
    };

    this._mockOpenBook = (filePath) => {
      return Promise.resolve({
        success: true,
        message: 'Opening book: ' + filePath,
      });
    };
  }

  _generateCallbackId() {
    return 'book_cb_' + Date.now() + '_' + this.callbackId++;
  }

  downloadBook(url, filename) {
    return new Promise((resolve, reject) => {
      const callbackId = this._generateCallbackId();
      
      this.callbacks[callbackId] = (result) => {
        delete this.callbacks[callbackId];
        resolve(result);
      };

      const message = JSON.stringify({
        action: 'downloadBook',
        callbackId: callbackId,
        url: url,
        filename: filename || 'book.epub',
      });

      if (window.BookBridge) {
        window.BookBridge.postMessage(message);
      } else {
        console.warn('BookBridge not available, using mock data');
        this._mockDownloadBook(url, filename).then(resolve);
      }
    });
  }

  getBookList() {
    return new Promise((resolve, reject) => {
      const callbackId = this._generateCallbackId();
      
      this.callbacks[callbackId] = (result) => {
        delete this.callbacks[callbackId];
        resolve(result);
      };

      const message = JSON.stringify({
        action: 'getBookList',
        callbackId: callbackId,
      });

      if (window.BookBridge) {
        window.BookBridge.postMessage(message);
      } else {
        console.warn('BookBridge not available, using mock data');
        this._mockGetBookList().then(resolve);
      }
    });
  }

  openBook(filePath) {
    return new Promise((resolve, reject) => {
      const callbackId = this._generateCallbackId();
      
      this.callbacks[callbackId] = (result) => {
        delete this.callbacks[callbackId];
        resolve(result);
      };

      const message = JSON.stringify({
        action: 'openBook',
        callbackId: callbackId,
        filePath: filePath,
      });

      if (window.BookBridge) {
        window.BookBridge.postMessage(message);
      } else {
        console.warn('BookBridge not available, using mock data');
        this._mockOpenBook(filePath).then(resolve);
      }
    });
  }
}

new BookBridge();

window.addEventListener('flutterBridgeMessage', (event) => {
  console.log('Received message from Flutter:', event.detail);
});
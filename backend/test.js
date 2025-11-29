const fs = require('fs');
try {
    fs.writeFileSync('test.log', 'Hello world');
    console.log('Done');
} catch (e) {
    console.error(e);
}

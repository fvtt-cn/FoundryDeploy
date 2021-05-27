const fs = require('fs');

const dest = process.argv[2];
const files = [
  `${dest}/files/files.mjs`,
  `${dest}/files/files.js`,
  `${dest}/packages/package.mjs`,
  `${dest}/packages/package.js`,
];

for (let file of files) {
  if (fs.existsSync(file)) {
    console.log(`Applying GHProxy Patch to ${file}`);
    let fileContent = fs.readFileSync(file, 'utf8');
    fileContent = fileContent.replace(/(const(.(?<!const))+?await fetch\((.+?)(?=,))/g,
      "if(!$3.includes('ghproxy.com/')&&($3.includes('github.com/')||$3.includes('raw.githubusercontent.com/')))$3='https://ghproxy.com/'+$3;$1");
    fs.writeFileSync(file, fileContent);
  }
}

#!/usr/bin/env bun

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, extname, join } from 'node:path';
import { parse } from 'yaml';

interface ConvertOptions {
  inputFile: string;
  outputFile?: string;
  indent?: number;
  pretty?: boolean;
}

function convertYamlToJson(options: ConvertOptions): void {
  const { inputFile, outputFile, indent = 2, pretty = true } = options;

  // 入力ファイルの存在確認
  if (!existsSync(inputFile)) {
    console.error(`❌ エラー: ファイル "${inputFile}" が見つかりません`);
    process.exit(1);
  }

  // ファイル拡張子の確認
  const ext = extname(inputFile).toLowerCase();
  if (!['.yaml', '.yml'].includes(ext)) {
    console.warn(
      `⚠️  警告: "${inputFile}" はYAMLファイルではない可能性があります`,
    );
  }

  try {
    // YAMLファイルを読み込み
    console.log(`📖 YAMLファイルを読み込み中: ${inputFile}`);
    const yamlContent = readFileSync(inputFile, 'utf8');

    // YAMLをパース
    const jsonData = parse(yamlContent);

    // 出力ファイル名を決定
    const outputFileName =
      outputFile ||
      join(dirname(inputFile) || '.', `${basename(inputFile, ext)}.json`);

    // JSONとして出力
    const jsonString = pretty
      ? JSON.stringify(jsonData, null, indent)
      : JSON.stringify(jsonData);

    writeFileSync(outputFileName, jsonString, 'utf8');

    console.log(`✅ 変換完了: ${outputFileName}`);
    console.log(
      `📊 サイズ: ${yamlContent.length} bytes (YAML) → ${jsonString.length} bytes (JSON)`,
    );
  } catch (error) {
    if (error instanceof Error) {
      console.error(`❌ 変換エラー: ${error.message}`);
    } else {
      console.error('❌ 不明なエラーが発生しました');
    }
    process.exit(1);
  }
}

// コマンドライン引数の処理
function main(): void {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes('-h') || args.includes('--help')) {
    console.log(`
🔄 YAML to JSON Converter

使用方法:
  bun run convert.ts <input.yaml> [output.json] [options]

引数:
  input.yaml    変換するYAMLファイルのパス
  output.json   出力JSONファイルのパス (省略可)

オプション:
  --compact     コンパクトなJSON出力 (改行・インデントなし)
  --indent=N    インデントのスペース数 (デフォルト: 2)
  -h, --help    このヘルプを表示

例:
  bun run convert.ts config.yaml
  bun run convert.ts config.yaml output.json
  bun run convert.ts config.yaml --compact
  bun run convert.ts config.yaml --indent=4
`);
    return;
  }

  const inputFile = args[0];
  let outputFile: string | undefined;
  let indent = 2;
  let pretty = true;

  // 引数をパース
  for (let i = 1; i < args.length; i++) {
    const arg = args[i];

    if (arg === '--compact') {
      pretty = false;
    } else if (arg.startsWith('--indent=')) {
      const indentValue = parseInt(arg.split('=')[1], 10);
      if (!Number.isNaN(indentValue) && indentValue >= 0) {
        indent = indentValue;
      }
    } else if (!arg.startsWith('--') && !outputFile) {
      outputFile = arg;
    }
  }

  convertYamlToJson({
    inputFile,
    outputFile,
    indent,
    pretty,
  });
}

// バッチ変換関数（複数ファイル対応）
export function convertMultipleFiles(
  inputFiles: string[],
  outputDir?: string,
): void {
  console.log(`🔄 ${inputFiles.length}個のファイルを変換中...`);

  for (const inputFile of inputFiles) {
    try {
      const outputFile = outputDir
        ? join(outputDir, `${basename(inputFile, extname(inputFile))}.json`)
        : undefined;

      convertYamlToJson({ inputFile, outputFile });
    } catch (error) {
      console.error(`❌ ${inputFile} の変換に失敗: ${error}`);
    }
  }

  console.log('🎉 バッチ変換完了！');
}

// スクリプトとして実行された場合
if (import.meta.main) {
  main();
}

(*
  ハーメルン小説ダウンローダー[hamelndl]

  1.0.7 2024/12/29  <style><script>タグ除去を追加した
                    行の先頭から全角空白が10個以上連続する場合、それらの空白を削除するようにした
  1.0.6 2024/12/19  ver1.0正式版リリース用にソースコードを再整理した
                    各話URL取得部分の検出タグを修正した
  1.0.5 2024/12/17  本文中の文字装飾タグ除去が不十分だった不具合を修正した
  1.0.4 2024/12/16  R18作品のダウンロードに対応した
                    短編のダウンロードに対応した
  1.0.3 2024/12/15  タイトルに連載状況を付加するようにした
                    丸傍点の処理を追加した
  1.0.2 2024/12/15  Naro2mobiから呼ばれた際のファイル名引き渡し不具合を修正した
                    Windowsメッセージ送信を修正した
  1.0.1 2024/12/15  1話目しか取得出来なかった不具合を修正した
                    各話タイトルの取得が不完全だった不具合を修正した
  1.0   2024/12/14  kakuyomdlのソースコードをテンプレートとしてハーメルン用として作成

ビルド方法：
  Lazarus(3.2以降)の場合：
    プロジェクトを開くからhamelndl.lpiを開いて実行メニューから構築する

  Delphi(XE2)以降の場合：
    プロジェクトを開くからhamelndl.dprojを開いて全てのプロジェクトをビルドで構築する

  どちらもTRegExprユニットが必要(https://github.com/andgineer/TRegExpr)
*)
program hamelndl;

{$APPTYPE CONSOLE}

{$IFDEF FPC}
  {$MODE Delphi}
  {$codepage utf8}
{$ENDIF}

{$R *.res}
{$R verinfo.res}

uses
{$IFDEF FPC}
  SysUtils,
  Classes,
  Messages,
  LazUTF8,
{$ELSE}
  LazUTF8wrap,
  System.SysUtils,
  System.Classes,
  WinAPI.Messages,
{$ENDIF}
  Windows,
  regexpr,
  WinInet;

const
  // バージョン
  VERSION  = 'ver1.07 2024/12/29';
  // データ抽出用の識別タグ(正規表現バージョン)
  // トップページ
  STITLE   = '<span .*?itemprop="name">.*?</span>';                                 // タイトル
  SAUTHER  = '<div align="right">作者：<span itemprop="author">.*?</span></div>';   // 作者
  SHEADER  = '<div class="ss">.*?<hr.*?></div>';                                    // 前書き部分
  SCONTENT = '<div class="ss">.*?<table .*?>.*?</div>';                             // 目次部分
  SCHAPTER = '<tr><td .*?><strong>.*?</strong></td></tr>';                          // 章(ないこともある)
  SSECTION = '<span id=".*?">.*?</span>';                                           // 話
  SSHORT   = '<div style=.*?>1 / 1</div>';                                          // 短編判別用
  // 短編
  SSTITLE  = '<span .*?><a href=\./>.*?</a></span>';                                // タイトル
  SSAUTHER = '作：<a href=".*?">.*?</a>';                                           // 作者
  SSMAEGAKI= '<div class="ss">.*?<';                                                // 前書き部分
  SSATOGAKI= '<div id="atogaki">.*?><br>.*?</div>';
  SSSECT   = '<span style=".*?"> .*?</span>';                                       // 話
  SSBODY   = '<div id="honbun">.*?</div>';                                          // 短編本文
  // 各話ページ
  SHEAD    = '<p><span.*?><a href=\./>.*?</a></span>';                              // タイトルまで
  SMAEGAKI = '<div id="maegaki">.*?</div>';                                         // 前書き
  SATOGAKI = '<div id="atogaki">.*?</div>';                                         // 後書き
  SPTITLE  = '<span .*?>.*?</span>';                                                // 各話タイトル
  SBODY    = '<div id="honbun">.*?</div>';                                          // 本文
  SLINEB   = '<p id=".*?">';                                                        // 行始まり
  SLINEE   = '</p>';                                                                // 行終わり
  SIMAGE   = '<a href=".*?" alt="挿絵".*?>【挿絵表示】</a>';                        // 挿絵

  // 青空文庫形式
  AO_RBI = '｜';							// ルビのかかり始め(必ずある訳ではない)
  AO_RBL = '《';              // ルビ始め
  AO_RBR = '》';              // ルビ終わり
  AO_TGI = '［＃';            // 青空文庫書式設定開始
  AO_TGO = '］';              //        〃       終了
  AO_CPI = '［＃「';          // 見出しの開始
  AO_CPT = '」は大見出し］';	// 章
  AO_SEC = '」は中見出し］';  // 話
  AO_PRT = '」は小見出し］';

  AO_CPB = '［＃大見出し］';        // 2022/12/28 こちらのタグに変更
  AO_CPE = '［＃大見出し終わり］';
  AO_SEB = '［＃中見出し］';
  AO_SEE = '［＃中見出し終わり］';
  AO_PRB = '［＃小見出し］';
  AO_PRE = '［＃小見出し終わり］';

  AO_DAI = '［＃ここから';		// ブロックの字下げ開始
  AO_DAO = '［＃ここで字下げ終わり］';
  AO_DAN = '字下げ］';
  AO_PGB = '［＃改丁］';			// 改丁と会ページはページ送りなのか見開き分の
  AO_PB2 = '［＃改ページ］';	// 送りかの違いがあるがどちらもページ送りとする
  AO_SM1 = '」に傍点］';			// ルビ傍点
  AO_SM2 = '」に丸傍点］';		// ルビ傍点 どちらもsesami_dotで扱う
  AO_EMB = '［＃丸傍点］';        // 横転開始
  AO_EME = '［＃丸傍点終わり］';  // 傍点終わり
  AO_KKL = '［＃ここから罫囲み］' ;     // 本来は罫囲み範囲の指定だが、前書きや後書き等を
  AO_KKR = '［＃ここで罫囲み終わり］';  // 一段小さい文字で表記するために使用する
  AO_END = '底本：';          // ページフッダ開始（必ずあるとは限らない）
  AO_PIB = '［＃リンクの図（';          // 画像埋め込み
  AO_PIE = '）入る］';        // 画像埋め込み終わり
  AO_LIB = '［＃リンク（';          // 画像埋め込み
  AO_LIE = '）入る］';        // 画像埋め込み終わり
  AO_CVB = '［＃表紙の図（';  // 表紙画像指定
  AO_CVE = '）入る］';        // 終わり

  CRLF   = #$0D#$0A;

// ユーザメッセージID
  WM_DLINFO  = WM_USER + 30;

var
  PageList,
  TextPage,
  LogFile: TStringList;
  TextLine,
  Capter, URL, Path, FileName,
  NvStat, StartPage: string;
  hWnd: THandle;
  CDS: TCopyDataStruct;
  StartN: integer;
  NShort: boolean;
  RegEx: TRegExpr;


// WinINetを用いたHTMLファイルのダウンロード
function LoadFromHTML(URLadr: string): string;
var
  hSession    : HINTERNET;
  hService    : HINTERNET;
  dwBytesRead : DWORD;
  dwFlag      : DWORD;
  lpBuffer    : PChar;
  RBuff       : TMemoryStream;
  TBuff       : TStringList;
begin
  Result   := '';
  // ハーメルンサイトのR18作品アクセス用Cookie
  InternetSetCookie(PChar(URLadr), PChar('over18'), PChar('off'));

  hSession := InternetOpen('WinINet', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);

  if Assigned(hSession) then
  begin
    dwFlag   := INTERNET_FLAG_RELOAD;
    hService := InternetOpenUrl(hSession, PChar(URLadr), nil, 0, dwFlag, 0);
    if Assigned(hService ) then
    begin
      RBuff := TMemoryStream.Create;
      try
        lpBuffer := AllocMem(65536);
        try
          dwBytesRead := 65535;
          while True do
          begin
            if InternetReadFile(hService, lpBuffer, 65535,{SizeOf(lpBuffer),}dwBytesRead) then
            begin
              if dwBytesRead = 0 then
                break;
              RBuff.WriteBuffer(lpBuffer^, dwBytesRead);
            end else
              break;
          end;
        finally
          FreeMem(lpBuffer);
        end;
        TBuff := TStringList.Create;
        try
          RBuff.Position := 0;
          TBuff.LoadFromStream(RBuff, TEncoding.UTF8);
          Result := TBuff.Text;
        finally
          TBuff.Free;
        end;
      finally
        RBuff.Free;
      end;
    end;
    InternetCloseHandle(hService);
  end;
end;

// 本文の改行タグを改行コードに変換する
function ChangeBRK(Base: string): string;
var
  str: string;
begin
  str    := UTF8StringReplace(Base, '<br />', #13#10, [rfReplaceAll]);
  str    := UTF8StringReplace(str, '<br/>',   #13#10, [rfReplaceAll]);
  Result := UTF8StringReplace(str, '<br>',    #13#10, [rfReplaceAll]);
end;

// 本文の青空文庫ルビ指定に用いられる文字があった場合誤作動しないように青空文庫代替表記に変換する(2022/3/25)
function ChangeAozoraTag(Base: string): string;
var
  tmp: string;
begin
  tmp := UTF8StringReplace(Base, '<rp>《</rp>', '<rp>(</rp>', [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '<rp>》</rp>', '<rp>)</rp>', [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '《', '※［＃始め二重山括弧、1-1-52］',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '》', '※［＃終わり二重山括弧、1-1-53］',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '｜', '※［＃縦線、1-1-35］',   [rfReplaceAll]);
  Result := tmp;
end;

// 本文の文字装飾を除去する
function EliminateDeco(Base: string): string;
var
  tmp: string;
begin
  RegEx.Expression  := '<span style=.*?>.*?</span>';  // 文字装飾
  RegEx.InputString := Base;
  while RegEx.Exec do
  begin
    tmp := RegEx.Match[0];
    tmp := ReplaceRegExpr('<span style=.*?>', tmp, '');
    tmp := ReplaceRegExpr('</span>', tmp, '');
    UTF8Delete(Base, RegEx.MatchPos[0], RegEx.MatchLen[0]); // 装飾範囲の文字列を削除
    UTF8Insert(tmp, Base, RegEx.MatchPos[0]);  // 変換後の文字列を挿入
    RegEx.InputString := Base;
  end;
  Result := Base;
end;

// 本文の傍点を青空文庫形式に変換する
function ChangeBouten(Base: string): string;
var
  tmp: string;
begin
  RegEx.Expression  := '<span class="\.sesame">.*?</span>';  // 傍点指定範囲
  RegEx.InputString := Base;
  while RegEx.Exec do
  begin
    tmp := RegEx.Match[0];
    tmp := ReplaceRegExpr('<span class="\.sesame">', tmp, '');
    tmp := ReplaceRegExpr('</span>', tmp, '');
    tmp := ReplaceRegExpr('<ruby><rb>', tmp, '');
    tmp := ReplaceRegExpr('</rb>.*?</ruby>', tmp, '');
    UTF8Delete(Base, RegEx.MatchPos[0], RegEx.MatchLen[0]);         // 傍点範囲の文字列を削除
    UTF8Insert(AO_EMB + tmp + AO_EME, Base, RegEx.MatchPos[0]);  // 変換後の文字列を挿入
    RegEx.InputString := Base;
  end;
  // 本文中の余計なタグを除去する
  Base := ReplaceRegExpr('<style>.*?</style>', Base, '');
  Base := ReplaceRegExpr('<script>.*?</script>', Base, '');

  Result := Base;
end;

// 本文のルビタグを青空文庫形式に変換する
function ChangeRuby(Base: string): string;
var
  tmp: string;
begin
  // <rp>タグを除去
  tmp := UTF8StringReplace(Base, '<rp>(</rp>', '', [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '<rp>)</rp>', '', [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '<rp>（</rp>', '', [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '<rp>）</rp>', '', [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '<rb>', '', [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '</rb>', '', [rfReplaceAll]);
  // rubyタグを青空文庫形式に変換
  tmp := UTF8StringReplace(tmp,  '<ruby>', AO_RBI, [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '<rt>',   AO_RBL, [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '</rt></ruby>', AO_RBR, [rfReplaceAll]);

  Result := tmp;
end;

// HTML特殊文字の処理
// 1)エスケープ文字列 → 実際の文字
// 2)&#x????; → 通常の文字
function Restore2RealChar(Base: string): string;
var
  tmp, cd: string;
  w: integer;
  ch: Char;
begin
  // エスケープされた文字
  tmp := UTF8StringReplace(Base, '&lt;',      '<',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '&gt;',      '>',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '&quot;',    '"',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '&nbsp;',    ' ',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '&yen;',     '\',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '&brvbar;',  '|',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '&copy;',    '©',  [rfReplaceAll]);
  tmp := UTF8StringReplace(tmp,  '&amp;',     '&',  [rfReplaceAll]);
  // &#????;にエンコードされた文字をデコードする(2023/3/19)
  // 正規表現による処理に変更した(2024/3/9)
  RegEx.Expression  := '&#.*?;';
  RegEx.InputString := tmp;
  if RegEx.Exec then
  begin
    repeat
      UTF8Delete(tmp, RegEx.MatchPos[0], RegEx.MatchLen[0]);
      cd := RegEx.Match[0];
      UTF8Delete(cd, 1, 2);           // &#を削除する
      UTF8Delete(cd, UTF8Length(cd), 1);  // 最後の;を削除する
      if cd[1] = 'x' then         // 先頭が16進数を表すxであればDelphiの16進数接頭文字$に変更する
        cd[1] := '$';
      try
        w := StrToInt(cd);
        ch := Char(w);
      except
        ch := '？';
      end;
      UTF8Insert(ch, tmp, RegEx.MatchPos[0]);
    until not RegEx.ExecNext;
  end;
  Result := tmp;
end;

// 埋め込まれた画像リンクを青空文庫形式に変換する
function ChangeImage(Base: string): string;
var
  str: string;
begin
  RegEx.Expression  := SIMAGE;
  RegEx.InputString := Base;
  while RegEx.Exec do
  begin
    str := RegEx.Match[0];
    str := ReplaceRegExpr('<a href="', str, AO_PIB);
    str := ReplaceRegExpr('" alt="挿絵" name=''img''>【挿絵表示】</a>', str, AO_PIE);
    UTF8Delete(Base, RegEx.MatchPos[0], RegEx.MatchLen[0]);
    UTF8Insert(str, Base, RegEx.MatchPos[0]);
    RegEx.InputString := Base;
  end;
  Result := Base;
end;

// 本文のリンクタグを除去する
function Delete_tags(Base: string): string;
begin
  Base := ReplaceRegExpr('<a href="', Base, '');
  Base := ReplaceRegExpr('">', Base, '');
  Base := ReplaceRegExpr('<.*?>', Base, '');

  Result := Base;
end;

// タイトル名をファイル名として使用出来るかどうかチェックし、使用不可文字が
// あれば修正する('-'に置き換える)
// フォルダ名の最後が'.'の場合、フォルダ作成時に"."が無視されてフォルダ名が
// 見つからないことになるため'.'も'-'で置き換える
// LazarusではUTF8文字列をインデックス(string[])でアクセス出来ないため、
// UTF8Copy, UTF8Delete, UTF8Insert処理で置き換える
{$IFDEF FPC}
function PathFilter(PassName: string): string;
var
  i, l: integer;
  path: string;
  tmp: AnsiString;
  ch: string;     // LazarusではCharにUTF-8の文字を代入できないためstringで定義する
begin
  // ファイル名を一旦ShiftJISに変換して再度Unicode化することでShiftJISで使用
  // 出来ない文字を除去する
  tmp := UTF8ToWinCP(PassName);
  path := WinCPToUTF8(tmp);      // これでUTF-8依存文字は??に置き換わる
  l :=  UTF8Length(path);
  for i := 1 to l do
  begin
    ch := UTF8Copy(path, i, 1); // i番目の文字を取り出す
    if Pos(ch, '\/;:*?"<>|. '+#$09) > 0 then // 文字種が使用不可であれば
    begin
      UTF8Delete(path, i, 1);                // 該当文字を削除して
      UTF8Insert('-', path, i);              // 代わりに'-'を挿入する
    end;
  end;
  Result := path;
end;
{$ELSE}  // Delphi
function PathFilter(PassName: string): string;
var
	i, l: integer;
  path: string;
  tmp: AnsiString;
  ch: char;
begin
  // ファイル名を一旦ShiftJISに変換して再度Unicode化することでShiftJISで使用
  // 出来ない文字を除去する
  tmp := AnsiString(PassName);
	path := string(tmp);
  l :=  Length(path);
  for i := 1 to l do
  begin
  	ch := Char(path[i]);
    if Pos(ch, '\/;:*?"<>|. '+#$09) > 0 then
      path[i] := '-';
  end;
  Result := path;
end;
{$ENDIF}

// タグ類処理(順番を間違えると誤作動する)
function ProcTags(Str: string): string;
var
  tmp: string;
begin
  tmp := ChangeAozoraTag(Str);
  tmp := ChangeBrk(tmp);
  tmp := EliminateDeco(tmp);
  tmp := ChangeBouten(tmp);
  tmp := Restore2RealChar(tmp);
  tmp := ChangeImage(tmp);
  tmp := ChangeRuby(tmp);
  Result := Delete_tags(tmp);
end;

// 小説本文をHTMLから抜き出して整形する
function ParsePage(Page: string): Boolean;
var
  sp, i: integer;
  header, footer, chapt, sect, body: string;
  lines: TStringList;
begin
  Result := True;
  // タイトル部分までのヘッダー要素を除去する
  RegEx.InputString := Page;
  RegEx.Expression  := SHEAD;
  if RegEx.Exec then
  begin
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  // 前書き
  header := '';
  RegEx.Expression  := SMAEGAKI;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    header := RegEx.Match[0];
    header := ReplaceRegExpr('<div id="maegaki">', header, '');
    header := ReplaceRegExpr('</div>', header, '');
    header := ProcTags(header);
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  // 章・話タイトル
  chapt := ''; sect := '';
  body := '';
  RegEx.Expression  := SPTITLE;    //<span .*?>.*?</span>
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    sect := RegEx.Match[0];
    sect := ReplaceRegExpr('<span .*?>', sect, '');
    sect := ReplaceRegExpr('</span>', sect, '');
    sect := ProcTags(sect);
    // 章タイトルが含まれていれば分離する
    sp := UTF8Pos(#13#10, sect);
    if sp > 0 then
    begin
      chapt := Trim(UTF8Copy(sect, 1, sp - 1));
      sect  := Trim(UTF8Copy(sect, sp + 2, Length(sect)));
    end else
      sect := Trim(sect);
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end else
    Result:= False;
  // 本文
  body := '';
  RegEx.Expression  := SBODY;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    body := RegEx.Match[0];
    body := ReplaceRegExpr('<div id="honbun">', body, '');
    body := ReplaceRegExpr('</div>', body, '');
    body := ChangeAozoraTag(body);
    body := ReplaceRegExpr('<p id=".*?">', body, '');  // 各行を整形
    body := ReplaceRegExpr('</p>', body, #13#10);
    body := ProcTags(body);
    // 全角空白が64個以上連続していた場合はダミーと判断して全て除去する
    lines := TStringList.Create;
    try
      lines.Text := body;
      RegEx.Expression := '　*';
      for i := 0 to lines.Count - 1 do
      begin
        RegEx.InputString := lines.Strings[i];
        if RegEx.Exec then
        begin
          if (RegEx.MatchPos[0] = 1) and (RegEx.MatchLen[0] > 10) then
          begin
            lines.Strings[i] := ReplaceRegExpr('　*', lines.Strings[i], '');
          end;
        end;
      end;
      body := lines.Text;
    finally
      lines.Free;
    end;
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end else
    Result := False;
  // 後書き
  footer := '';
  RegEx.Expression  := SATOGAKI;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    footer := RegEx.Match[0];
    footer := ReplaceRegExpr('<div id="atogaki">', footer, '');
    footer := ReplaceRegExpr('</div>', footer, '');
    footer := ProcTags(footer);
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  if chapt <> '' then
    TextPage.Add(AO_CPB + chapt + AO_CPE);
  TextPage.Add(AO_SEB + sect + AO_SEE);
  if header <> '' then
    TextPage.Add(AO_KKL + header + #13#10 + AO_KKR);
  if body <> '' then
    TextPage.Add(body)
  else
    TextPage.Add('★HTMLページ読み込みエラー');
  if footer <> '' then
    TextPage.Add(AO_KKL + footer + #13#10 + AO_KKR);
  TextPage.Add('');
  TextPage.Add(AO_PB2);
  TextPage.Add('');

  if Result = False then
    Writeln(sect + ' から本文を抽出出来ませんでした.');
end;

// 各話URLリストをもとに各話ページを読み込んで本文を取り出す
procedure LoadEachPage;
var
  i, n, cnt, sc: integer;
  line: string;
  CSBI: TConsoleScreenBufferInfo;
  CCI: TConsoleCursorInfo;
  hCOutput: THandle;
begin
  cnt := PageList.Count;
  hCOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hCOutput, CSBI);
  GetConsoleCursorInfo(hCOutput, CCI);
  Write('各話を取得中 [  0/' + Format('%3d', [cnt]) + ']');
  CCI.bVisible := False;
  SetConsoleCursorInfo(hCoutput, CCI);
  if StartN > 0 then
    i := StartN - 1
  else
    i := 0;
  n := 1;
  sc := cnt - i;

  while i < cnt do
  begin
    line := LoadFromHTML(PageList.Strings[i]);
    if line <> '' then
    begin
      if not ParsePage(line) then
        Break;
      SetConsoleCursorPosition(hCOutput, CSBI.dwCursorPosition);
      Write('各話を取得中 [' + Format('%3d', [i + 1]) + '/' + Format('%3d', [cnt]) + '(' + Format('%d', [(n * 100) div sc]) + '%)]');
      if hWnd <> 0 then
        SendMessage(hWnd, WM_DLINFO, n, 1);
      // サーバーへの負担を減らすため1秒のインターバルを入れる
      Sleep(1000);   // Sleep処理を削除したり、この数値を小さくすることを禁止します
    end;
    Inc(i);
    Inc(n);
  end;
  CCI.bVisible := True;
  SetConsoleCursorInfo(hCoutput, CCI);
  Writeln('');
end;

// 短編専用処理
procedure ParseShort(Page: string);
var
  title, auther, authurl, header, sect, body, footer: string;
begin
  // タイトル
  RegEx.Expression  := SSTITLE;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    title := RegEx.Match[0];
    title := ReplaceRegExpr('<span .*?><a href=\./>', title, '');
    title := ReplaceRegExpr('</a></span>', title, '');
    title := ProcTags('【短編】' + title);
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
    // ファイル名を準備する
    if FileName = '' then
      FileName := Path + PathFilter(title) + '.txt';
  end;
  // 作者・作者URL
  RegEx.Expression  := SSAUTHER;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    auther := RegEx.Match[0];
    authurl:= auther;
    auther := ReplaceRegExpr('作：<a href=".*?">', auther, '');
    auther := ReplaceRegExpr('</a>', auther, '');
    auther := ProcTags(auther);
    authurl:= ReplaceRegExpr('作：<a href="', authurl, '');
    authurl:= ReplaceRegExpr('">.*?</a>', authurl, '');
    if authurl <> '' then
      authurl:= 'https:' + authurl;
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  // 前書き
  header := '';
  RegEx.Expression  := SSMAEGAKI;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    header := RegEx.Match[0];
    header := ReplaceRegExpr('<div class="ss">', header, '');
    header := ReplaceRegExpr('<', header, '');
    header := ProcTags(header);
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  // 話タイトル
  sect := '';
  RegEx.Expression  := SSSECT;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    sect := RegEx.Match[0];
    sect := ReplaceRegExpr('<span style="font-size:120%">', sect, '');
    sect := ReplaceRegExpr('</span>', sect, '');
    sect := ProcTags(Trim(sect));
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  // 本文
  body := '';
  RegEx.Expression  := SSBODY;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    body := RegEx.Match[0];
    body := ReplaceRegExpr('<div id="honbun">', body, '');
    body := ReplaceRegExpr('</div>', body, '');
    body := ReplaceRegExpr('<div id="honbun">', body, '');
    body := ReplaceRegExpr('</div>', body, '');
    body := ChangeAozoraTag(body);
    body := ReplaceRegExpr('<p id=".*?">', body, '');  // 各行を整形
    body := ReplaceRegExpr('</p>', body, #13#10);
    body := ProcTags(body);
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  // 後書き
  footer := '';
  RegEx.Expression  := SSATOGAKI;
  RegEx.InputString := Page;
  if RegEx.Exec then
  begin
    footer := RegEx.Match[0];
    footer := ReplaceRegExpr('<div id="atogaki">', footer, '');
    footer := ReplaceRegExpr('</div>', footer, '');
    footer := ProcTags(footer);
    UTF8Delete(Page, 1, RegEx.MatchPos[0] + RegEx.MatchLen[0] - 1);
  end;
  TextPage.Add(title);
  TextPage.Add(auther);
  TextPage.Add(AO_PB2);
  if header <> '' then
  begin
    TextPage.Add(AO_KKL + URL + #13#10 + header + #13#10 + AO_KKR);
    TextPage.Add(AO_PB2);
  end;
  TextPage.Add(AO_SEB + sect + AO_SEE);
  TextPage.Add(body);
  if footer <> '' then
    TextPage.Add(AO_KKL + footer + #13#10 + AO_KKR);
  TextPage.Add(AO_PB2);

  LogFile.Add(title);
  if authurl <> '' then
    LogFile.Add(auther + '(https:' + authurl + ')')
  else
    LogFile.Add(auther);
  LogFile.Add('');
  LogFile.Add(header);
  LogFile.Add('');
end;

// トップページからタイトル、作者、前書き、各話情報を取り出す
procedure ParseCapter(MainPage: string);
var
  sp, sc, sl, pn: integer;
  title, auther, authurl, header, cont, sendstr: string;
  conhdl: THandle;
begin
  Write('小説情報を取得中 ' + URL + ' ... ');
  authurl := '';
  // 短編かどうかをチェックする
  RegEx.Expression  := SSHORT;
  RegEx.InputString := MainPage;
  NShort := RegEx.Exec;
  if NShort then
  begin
    ParseShort(MainPage);
  end else begin
    // タイトル名
    title := '';
    RegEx.Expression  := STITLE;
    RegEx.InputString := MainPage;
    if RegEx.Exec then
    begin
      sp := RegEx.MatchPos[0] + RegEx.MatchLen[0];
      title := RegEx.Match[0];
      // タイトルの前後のタグを除去する
      title := ReplaceRegExpr('<span .*?itemprop="name">', title, '');
      title := ReplaceRegExpr('</span>', title, '');
      title := ProcTags(title);
      UTF8Delete(MainPage, 1, sp - 1);
      // ファイル名を準備する
      if FileName = '' then
        FileName := Path + PathFilter(title) + '.txt';
      // 作者名
      auther := ''; authurl := '';
      RegEx.Expression := SAUTHER;
      RegEx.InputString:= MainPage;
      if RegEx.Exec then
      begin
        sp := RegEx.MatchPos[0] + RegEx.MatchLen[0];
        auther := RegEx.Match[0];
        // 作者名の前後のタグを除去する
        auther := ReplaceRegExpr('<div align="right">作者：<span itemprop="author">', auther, '');
        auther := ReplaceRegExpr('</span></div>', auther, '');
        UTF8Delete(MainPage, 1, sp - 1);
        RegEx.InputString := auther;
        RegEx.Expression  := '<a href=.*?>';
        if RegEx.Exec then
        begin
          authurl := RegEx.Match[0];
          authurl := ReplaceRegExpr('<a href="', authurl, '');
          authurl := ReplaceRegExpr('">', authurl, '');
          auther := ReplaceRegExpr('<.*?>', auther, '');
        end;
        auther := ProcTags(auther);
      end;
      // 前書き部分
      RegEx.Expression := SHEADER;
      RegEx.InputString:= MainPage;
      if RegEx.Exec then
      begin
        sp := RegEx.MatchPos[0] + RegEx.MatchLen[0];
        header := RegEx.Match[0];
        // 前書きの前後のタグを除去する
        header := ReplaceRegExpr('<div class="ss">', header, '');
        header := ReplaceRegExpr('<hr.*?></div>', header, '');
        header := ProcTags(header);
        UTF8Delete(MainPage, 1, sp - 1);
      end;
      // 目次部分
      pn := 1;
      RegEx.Expression := SCONTENT;
      RegEx.InputString:= MainPage;
      if RegEx.Exec then
      begin
        cont := RegEx.Match[0];
        // 作者名の前後のタグを除去する
        cont := ReplaceRegExpr('<div class="ss">', cont, '');
        cont := ReplaceRegExpr('</div>', cont, '');
      end;
      // 目次を取り出す
      while True do
      begin
        RegEx.Expression := SSECTION;
        RegEx.InputString:= cont;
        // ここでは目次ああるかどうかだけをチェックして各話URLを簡易的に登録していく
        if RegEx.Exec then
        begin
          sc := RegEx.MatchPos[0];
          sl := RegEx.MatchLen[0];
          PageList.Add(URL + IntToStr(pn) + '.html');
          Inc(pn);
          UTF8Delete(cont, 1, sc + sl - 1);
        end else
          Break;
      end;
      // タイトル名に"完結"が含まれていなければ先頭に小説の連載状況を追加する
      if UTF8Pos('完結', title) = 0 then
        title := NvStat + title;
      TextPage.Add(title);
      TextPage.Add(auther);
      TextPage.Add(AO_PB2);
      TextPage.Add(AO_KKL + URL + #13#10 + header + #13#10 + AO_KKR);
      TextPage.Add(AO_PB2);
      LogFile.Add(title);
      if authurl <> '' then
        LogFile.Add(auther + '(https:' + authurl + ')')
      else
        LogFile.Add(auther);
      LogFile.Add('');
      LogFile.Add(header);
      LogFile.Add('');
      Writeln(IntToStr(PageList.Count) + ' 話の情報を取得しました.');
      // Naro2mobiから呼び出された場合は進捗状況をSendする
      if hWnd <> 0 then
      begin
        conhdl := GetStdHandle(STD_OUTPUT_HANDLE);
        sendstr := title + ',' + auther;
        Cds.dwData := PageList.Count - StartN + 1;
        Cds.cbData := (Length(sendstr) + 1) * SizeOf(Char);
        Cds.lpData := Pointer(sendstr);
        SendMessage(hWnd, WM_COPYDATA, conhdl, LPARAM(Addr(Cds)));
      end;
    end else
      Writeln('トップページから情報を取得出来ませんでした.');
  end;
end;

// 小説の連載状況をチェックする
function GetNovelStatus(MainPage: string): string;
var
  str: string;
begin
  Result := '';
  if MainPage <> '' then
  begin
    // トップページから作品情報ページURLを取得して連載状況を確認する
    RegEx.Expression  := '<li><a href="//syosetu.org/\?mode=ss_detail&nid=.*?">小説情報</a></li>';
    RegEx.InputString := MainPage;
    if RegEx.Exec then
    begin
      str := RegEx.Match[0];
      str := UTF8StringReplace(str, '<li><a href="', '', [rfReplaceAll]);
      str := UTF8StringReplace(str, '">小説情報</a></li>', '', [rfReplaceAll]);
      str := LoadFromHTML('https:' + str);
      if UTF8Pos('連載(完結)', str) > 0 then
        Result := '【完結】'
      else if UTF8Pos('連載(連載中)', str) > 0 then
        Result := '【連載中】';
    end;
  end;
end;

var
  i: integer;
  op: string;

begin
  if ParamCount = 0 then
  begin
    Writeln('');
    Writeln('hamelndl ' + VERSION + ' (c) INOUE, masahiro.');
    Writeln('  使用方法');
    Writeln('  hamelndl [-sDL開始ページ番号] 小説トップページのURL [保存するファイル名(省略するとタイトル名で保存します)]');
    Exit;
  end;
  ExitCode  := 0;
  hWnd      := 0;
  StartN    := 0;  // 開始ページ番号(0スタート)
  FileName  := '';
  StartPage := '';

  Path := ExtractFilePath(ParamStr(0));
  // オプション引数取得
  for i := 0 to ParamCount - 1 do
  begin
    op := ParamStr(i + 1);
    // Naro2mobiのWindowsハンドル
    if UTF8Pos('-h', op) = 1 then
    begin
      Delete(op, 1, 2);
      try
        hWnd := StrToInt(op);
      except
        Writeln('Error: Invalid Naro2mobi Handle.');
        ExitCode := -1;
        Exit;
      end;
    // DL開始ページ番号
    end else if UTF8Pos('-s', op) = 1 then
    begin
      Delete(op, 1, 2);
      StartPage := op;
      try
        StartN := StrToInt(op);
      except
        Writeln('Error: Invalid Start Page Number.');
        ExitCode := -1;
        Exit;
      end;
    // 作品URL
    end else if UTF8Pos('https:', op) = 1 then
    begin
      URL := op;
    // それ以外であれば保存ファイル名
    end else begin
      FileName := op;
      if UpperCase(ExtractFileExt(op)) <> '.TXT' then
        FileName := FileName + '.txt';
    end;
  end;

  if UTF8Pos('https://syosetu.org/novel/', URL) = 0 then
  begin
    Writeln('小説のURLが違います.');
    ExitCode := -1;
    Exit;
  end;

  Capter := '';
  TextLine := LoadFromHTML(URL);
  if TextLine <> '' then
  begin
    PageList := TStringList.Create;         // 各話ページのURLを保存
    TextPage := TStringList.Create;         // 作品テキスト格納用
    LogFile  := TStringList.Create;         // ログファイル用
    RegEx    := TRegExpr.Create;            // 正規表現処理インスタンス

    LogFile.Add(URL);
    try
      NvStat := GetNovelStatus(TextLine);   // 小説の連載状況を取得
      ParseCapter(TextLine);                // 小説の目次情報を取得
      if (PageList.Count >= StartN) or NShort then
      begin
        if not NShort then                  // 短編でなければ各話情報を取得
          LoadEachPage;
        if FileName <> '' then
        begin
          try
            TextPage.WriteBOM := True;      // DelphiとLazarusでデフォルトの定義が違うため明示的に指定する
            LogFile.WriteBOM  := True;
            TextPage.SaveToFile(Filename, TEncoding.UTF8);
            LogFile.SaveToFile(ChangeFileExt(FileName, '.log'), TEncoding.UTF8);
            Writeln(ExtractFileName(Filename) + ' に保存しました.');
          except
            ExitCode := -1;
            Writeln('ファイルの保存に失敗しました.');
          end;
        end else
          Writeln(URL + 'から小説情報を取得できませんでした.');
      end else begin
        Writeln(URL + 'から小説情報を取得できませんでした.');
        ExitCode := -1;
      end;
    finally
      RegEx.Free;
      LogFile.Free;
      PageList.Free;
      TextPage.Free;
    end;
  end else begin
    Writeln(URL + 'からページ情報を取得できませんでした.');
    ExitCode := -1;
  end;
  //Readln;
end.

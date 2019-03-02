{ 1.44MB floppy holds 18 sectors/track - totally 80 tracks/side, doublesided }
const
  driveNo : byte = 0;
  sfxImage : boolean = false;
  imaSfx : boolean = false;

var
  imageFile : string;
  driveName : string;
  buf : array[1..512*18] of char;
  f : file;
  side, track, sector, res : byte;
  y : integer;
  c : char;

function ucase(s : string) : string;
var
  x : byte;
begin
  for x := 1 to length(s) do
    s[x] := upcase(s[x]);
  ucase := s;
end;

function readkey : char; assembler;
asm
  mov  ah, 0
  int  16h
end;

procedure gotoxy(x, y : byte); assembler;
asm
  mov  ah, 2                                  (* function *)
  mov  dh, y                                  (* row *)
  mov  dl, x                                  (* column *)
  dec  dh                                     
  dec  dl                                     
  mov  bh, 0                                  (* page *)
  int  10h                                    (* execute *)
end;

function wherex : byte; assembler;
asm
  mov  ah, 3                                  (* function *)
  mov  bh, 0                                  (* page *)
  int  10h                                    (* run *)
  inc  dl                                        
  mov  al, dl                                 (* return *)
end;

function wherey : byte; assembler;
asm
  mov  ah, 3                                  (* function *)
  mov  bh, 0                                  (* page *)
  int  10h                                    (* run *)
  inc  dh                                        
  mov  al, dh                                 (* return *)
end;

function split(path : string) : string;
var
  x : integer;
  s : string;
begin
  s := '';
  for x := length(path) downto 1 do begin
    if (path[x] = '\') or (path[x] = '/') then break;
    s := path[x] + s;
  end;
  split := s;
end;

function int2str(i : integer) : string;
var
  s : string;
begin
  str(i, s);
  int2str := s;
end;

function one(s : string) : char;
begin
  one := s[1];
end;

function sect(op, side, track, sect : byte) : byte; assembler;
asm
  lea bx, buf                (* es:bx point to our buffer *)
  mov ax, ds
  mov es, ax

  mov ah, op                 (* read/write *)
  mov al, 18     			 (* sectorcount *)
  mov dl, driveNo            (* drive *)
  mov dh, side               (* side (1 or 0) *)
  mov ch, track              (* track *)
  mov cl, sect               (* sector *)
  int 13h

  mov al, 0
  jnc @end
  mov al, ah
  @end:
end;

procedure doRestore;
label
  restoreResume;
begin
  writeln('Restoring Image ''' + ucase(split(imageFile)) + '''');
  assign(f, imageFile);
  reset(f, 1);
  if imaSfx = true then begin
    seek(f, filesize(f) - 80*2*18*512);
  end;
  write('Restoring ' + driveName + ', ');

  for track := 0 to 79 do begin
    for side := 0 to 1 do begin
      gotoxy(15, wherey);
      write('Head ' + int2str(side) + ', Track ' + int2str(track) + ', Sector #1-18');
      sector := 1;
      while sector < 19 do begin
        blockread(f, buf, sizeof(buf));
        res := Sect(3, side, track, sector);
        if res <> 0 then begin
          { error... try 3 times... }
          for y := 1 to 3 do begin
            asm { reset diskdrive }
              mov ah, 0
              int 13h
            end;
            if sect(3, side, track, sector) = 0 then goto restoreResume;
          end;
          writeln;
          writeln('Error #' + int2str(res) + ', Aborting');
          close(f);
          exit;
        end;
        restoreResume:
        sector := sector + 18;
      end;
    end;
  end;

  close(f);
  gotoxy(1, wherey);
  write('==> 100% ' + ucase(split(imageFile)));
  while wherex <> 80 do write(' ');
  writeln;
end;

procedure doImage;
label
  imageResume;
var
  numRead, numWritten : word;
  j : file;
begin
  if sfxImage = true then begin
    if pos('.', split(imageFile)) = 0 then
      imageFile := imageFile + '.EXE';
  end else
    if pos('.', split(imageFile)) = 0 then
      imageFile := imageFile + '.IMG';

  writeln('Creating Image ''' + ucase(split(imageFile)) + '''');
  assign(f, imageFile);
  rewrite(f, 1);
  if sfxImage = true then begin
    write('Building SFX Header...');
    assign(j, paramStr(0));
    reset(j, 1);
    repeat
      blockRead(j, buf, sizeOf(Buf), numRead);
      blockWrite(f, buf, numRead, numWritten);
    until (numRead = 0) or (numWritten <> numRead);
    close(j);
    writeln(' OK');
  end;

  write('Imaging ' + driveName + ', ');

  for track := 0 to 79 do begin
    for side := 0 to 1 do begin
      gotoxy(13, wherey);
      write('Head ' + int2str(side) + ', Track ' + int2str(track) + ', Sector #1-18');
      sector := 1;
      while sector < 19 do begin
        res := Sect(2, side, track, sector);
        if res <> 0 then begin
          { error... try 3 times... }
          for y := 1 to 3 do begin
            asm { reset diskdrive }
              mov ah, 0
              int 13h
            end;
            if sect(2, side, track, sector) = 0 then goto imageResume;
          end;
          writeln;
          writeln('Error #' + int2str(res) + ', Aborting');
          close(f);
          exit;
        end;
        imageResume:
        blockwrite(f, buf, sizeof(buf));
        sector := sector + 18;
      end;
    end;
  end;

  close(f);
  gotoxy(1, wherey);
  write('==> 100% ' + ucase(split(imageFile)));
  while wherex <> 80 do write(' ');
  writeln;
end;

procedure doHelp;
begin
  writeln('DI [/R] [/S] [Drive] [Filename]');
  writeln;
  writeln('  [Drive]     Source or Destination diskdrive');
  writeln('  [Filename]  Name of file to create or read');
  writeln('  /R          Restore [Filename] to [Drive]');
  writeln('  /S          Create SelF-eXtracting image (.EXE)');
end;

begin
  if wherex <> 1 then writeln;
  write('DiskImager 1.1, Copyright (C) 1999 by Port Jackson Computing');
  imaSfx := false;
  imageFile := '';
  driveName := '';

  assign(f, paramStr(0));
  reset(f, 1);
  if (fileSize(f) > 15668) then begin
    writeln(' - SFX Image');
    imaSfx := true;
  end else writeln;
  close(f);
  writeln;

  { find drive }
  for y := 1 to paramCount do begin
    if ucase(paramStr(y)) = 'A:' then begin
      driveName := 'A:';
      driveNo := 0;
      break;
    end;
    if ucase(paramStr(y)) = 'B:' then begin
      driveName := 'B:';
      driveNo := 1;
      break;
    end;
  end;

  if (imaSfx = true) and (driveName = '') then begin
    { we are a sfx archive & the user didnt specify destination }
    write('Drive where to Restore Image: ');
    c := readkey;
    if (upcase(c) = 'A') then begin
      writeln('A:');
      driveName := 'A:';
      driveNo := 0;
    end;
    if (upcase(c) = 'B') then begin
      writeln('B:');
      driveName := 'B:';
      driveNo := 0;
    end;
    if (driveName = '') then begin
      writeln(split(paramStr(0)) + ' [Drive to Restore Image to]');
      exit;
    end;
  end;

  if (imaSfx = true) then begin
    { im a sfx, the user has specified the destination }
    imageFile := paramStr(0);
    doRestore;
    exit;
  end;

  { find filename }
  for y := 1 to paramCount do begin
    if (ucase(paramStr(y)) <> 'A:') and (ucase(paramStr(y)) <> 'B:')
      and (one(paramStr(y)) <> '/') then begin
      imageFile := paramStr(y);
      break;
    end;
  end;

  { check parameters }
  for y := 1 to paramCount do begin
    if (ucase(paramStr(y)) = '/R') then begin
      if (imageFile <> '') and (driveName <> '') then begin
        doRestore;
        exit;
      end else begin
        doHelp;
        exit;
      end;
    end;
  end;

  for y := 1 to paramCount do begin
    if (ucase(paramStr(y)) = '/S') then begin
      sfxImage := true;
      break;
    end;
  end;

  if (imageFile <> '') and (driveName <> '') then begin
    doImage;
    exit;
  end;

  doHelp;
end.
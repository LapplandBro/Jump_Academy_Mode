enum DLType {
	DL_None,
	DL_Index,
	DL_Prefetch,
	DL_Play,
	DL_Clean
}

#define FileInfo_iType			0
#define FileInfo_bConcat		1
#define FileInfo_hFile			2
#define FileInfo_sPage			3
#define FileInfo_aData			4

#define REPO_LISTING_PAGE	"/jumpbot/listings"
#define REPO_FETCH_PAGE		"/jumpbot/fetch"
#define INDEX_FILE_NAME		"index.cfg"

#define MAX_RETRIES		5

void FetchRecording(Recording iRecording, bool bPrefetchOnly = false) {
	if (!g_bSocketExtension || !g_hUseRepo.BoolValue || !iRecording || iRecording.Downloading) {
		return;
	}
	
	char sFilePath[PLATFORM_MAX_PATH];
	iRecording.GetFilePath(sFilePath, sizeof (sFilePath));
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CACHE_FOLDER);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}
	
	File hFile = OpenFile(sFilePath, "wb");
	if (hFile == null) {
		LogError("%T: %s", "Cannot File Write", LANG_SERVER, sPath);
		return;
	}
	
	Handle hSocket = SocketCreate(SOCKET_TCP, OnSocketError);
	if (hSocket == INVALID_HANDLE) {
		LogError("%T: INVALID_HANDLE", "Socket Error", LANG_SERVER, -1, -1);
		return;
	}
	SocketSetOption(hSocket, ConcatenateCallbacks, 4096);
	
	ArrayList hFileInfo = new ArrayList(ByteCountToCells(64));
	if (bPrefetchOnly) {
		hFileInfo.Push(DL_Prefetch);
	} else {
		hFileInfo.Push(DL_Play);
	}
	hFileInfo.Push(false);
	hFileInfo.Push(hFile);

	char sHash[41];
	strcopy(sHash, sizeof(sHash), sFilePath[strlen(sFilePath)-40]);
	
	char sPage[64];
	FormatEx(sPage, sizeof(sPage), "%s?hash=%s", REPO_FETCH_PAGE, sHash);
	hFileInfo.PushString(sPage);
	hFileInfo.Push(iRecording);
	iRecording.Downloading = 1;
	
	SocketSetArg(hSocket, hFileInfo);
	SocketConnect(hSocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, API_HOST, 80);
}

void FetchRepository() {
	if (!g_bSocketExtension || !g_hUseRepo.BoolValue) {
		return;
	}
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CACHE_FOLDER);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s/%s", CACHE_FOLDER, INDEX_FILE_NAME);
	File hFile = OpenFile(sPath, "w");
	if (hFile == null) {
		LogError("%T: %s", "Cannot File Write", LANG_SERVER, sPath);
		return;
	}
	
	Handle hSocket = SocketCreate(SOCKET_TCP, OnSocketError);
	if (hSocket == INVALID_HANDLE) {
		LogError("%T: INVALID_HANDLE", "Socket Error", LANG_SERVER, -1, -1);
		return;
	}
	
	SocketSetOption(hSocket, ConcatenateCallbacks, 4096);
	
	ArrayList hFileInfo = new ArrayList(ByteCountToCells(64));
	hFileInfo.Push(DL_Index);
	hFileInfo.Push(false);
	hFileInfo.Push(hFile);
	
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));
	
	char sPage[64];
	FormatEx(sPage, sizeof(sPage), "%s?map=%s&version=%d.%d", REPO_LISTING_PAGE, sMapName, REC_FORMAT_VERSION_MAJOR, REC_FORMAT_VERSION_MINOR);
	hFileInfo.PushString(sPage);
	SocketSetArg(hSocket, hFileInfo);
	SocketConnect(hSocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, API_HOST, 80);
}

void FetchHashes(File hFile, any aData) {
	if (!g_bSocketExtension || !g_hUseRepo.BoolValue) {
		return;
	}	
	
	Handle hSocket = SocketCreate(SOCKET_TCP, OnSocketError);
	if (hSocket == INVALID_HANDLE) {
		LogError("%T: INVALID_HANDLE", "Socket Error", LANG_SERVER, -1, -1);
		return;
	}
	SocketSetOption(hSocket, ConcatenateCallbacks, 4096);
	
	ArrayList hFileInfo = new ArrayList(ByteCountToCells(64));
	hFileInfo.Push(DL_Clean);
	hFileInfo.Push(false);
	hFileInfo.Push(hFile);

	char sPage[64];
	FormatEx(sPage, sizeof(sPage), "%s?hashes=1", REPO_LISTING_PAGE);
	hFileInfo.PushString(sPage);
	hFileInfo.Push(aData);
	
	SocketSetArg(hSocket, hFileInfo);
	SocketConnect(hSocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, API_HOST, 80);
}

public int OnSocketError(Handle hSocket, const int iErrorType, const int iErrorNum, any aArg) {
	CloseHandle(hSocket);
	LogError("%T", "Socket Error", LANG_SERVER, iErrorType, iErrorNum);
	
	ArrayList hFileInfo = aArg;
	File hFile = hFileInfo.Get(FileInfo_hFile);
	delete hFile;
	
	if (hFileInfo.Get(FileInfo_iType) == DL_Play) {
		g_iClientInstruction = INST_NOP;
		if (Client_IsValid(g_iClientOfInterest) && IsClientInGame(g_iClientOfInterest)) {
			PrintHintText(g_iClientOfInterest, " ");
			StopSound(g_iClientOfInterest, SNDCHAN_STATIC, "ui/hint.wav");
			CreateTimer(0.1, Timer_CloseHintPanel, g_iClientOfInterest, TIMER_FLAG_NO_MAPCHANGE);
			
			if (g_iClientInstructionPost == INST_RETURN) {
				doRespawn(g_iClientOfInterest);
			}
		}
	}
	
	if (g_hDebug.BoolValue && Client_IsValid(g_iClientOfInterest) && IsClientInGame(g_iClientOfInterest)) {
		CPrintToChat(g_iClientOfInterest, "{green}[{lightgreen}jb{green}] {white}%t", "Download Fail");
	}
	
	char sPage[64];
	hFileInfo.GetString(FileInfo_sPage, sPage, sizeof(sPage));
	LogError("%T: %s", "Cannot Download Rec", LANG_SERVER, sPage);
	
	DLType iType = hFileInfo.Get(FileInfo_iType);
	if (iType == DL_Prefetch || iType == DL_Play) {
		Recording iRecording = view_as<Recording>(hFileInfo.Get(FileInfo_aData));

		char sFilePath[PLATFORM_MAX_PATH];
		iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
		DeleteFile(sFilePath);
		
		if (iRecording.Downloading++ < MAX_RETRIES) {
			FetchRecording(iRecording, iType == DL_Prefetch);
		} else if (iType == DL_Play) {
			g_iClientInstruction = INST_NOP;
			doReturn();
		}
	}
	
	delete hFileInfo;

	return 0;
}

public int OnSocketConnected(Handle hSocket, any aArg) {
	char sRequest[4096];
	char sPage[64];
	
	ArrayList hFileInfo = aArg;
	hFileInfo.GetString(FileInfo_sPage, sPage, sizeof(sPage));
	
	if (g_hDebug.BoolValue) {
		CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Установка соединения с: %s", sPage);
	}
	
	FormatEx(sRequest, sizeof(sRequest), "GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\nCache-Control: no-cache, no-store, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n", sPage, API_HOST);
	SocketSend(hSocket, sRequest);

	return 0;
}

public int OnSocketReceive(Handle hSocket, char[] sData, const int iSize, any aArg) {
	ArrayList hFileInfo = aArg;
	File hFile = hFileInfo.Get(FileInfo_hFile);
	if (!hFileInfo.Get(FileInfo_bConcat)) {
		if (strncmp(sData, "HTTP/", 5) == 0 && strncmp(sData[9], "200", 3) == 0) {
			if (g_hDebug.BoolValue) {
				CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Получен HTTP OK заголовок.");
			}
			
			hFileInfo.Set(FileInfo_bConcat, true);
			
			DLType iType = hFileInfo.Get(FileInfo_iType);
			if (iType == DL_Prefetch || iType == DL_Play) {
				int iFSOffset = StrContains(sData[16], "Content-Length: ");
				int iFSLength = StrContains(sData[16+iFSOffset + 16], "\r\n");
				if (iFSOffset != -1 && iFSLength > 0) {
					char[] sFileSize = new char[iFSLength+1];
					strcopy(sFileSize, iFSLength+1, sData[16+iFSOffset+16]);
					
					Recording iRecording = view_as<Recording>(hFileInfo.Get(FileInfo_aData));
					iRecording.FileSize = StringToInt(sFileSize);
					
					if (g_hDebug.BoolValue) {
						CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Content-Length: %s байт", sFileSize);
						CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Начальный размер пакета: %d байт", iSize-(StrContains(sData[16], "\r\n\r\n")+16+4));
					}
				}
			}
			
			int iOffset = StrContains(sData[16], "\r\n\r\n")+16+4;
			for (int i=iOffset; i<iSize; i++) {
				hFile.WriteInt8(sData[i]);
			}
		} else {
			char sPage[64];
			hFileInfo.GetString(FileInfo_sPage, sPage, sizeof(sPage));
			LogError("%T", "Unexpected Response", LANG_SERVER, sData[9], sData[10], sData[11], sPage);
			CloseHandle(hSocket);
		}
	} else {
		if (g_hDebug.BoolValue) {
			CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Получен пакет: %d байт", iSize);
		}
		
		for (int i=0; i<iSize; i++) {
			hFile.WriteInt8(sData[i]);
		}
	}

	return 0;
}

public int OnSocketDisconnected(Handle hSocket, any aArg) {
	ArrayList hFileInfo = aArg;
	File hFile = hFileInfo.Get(FileInfo_hFile);
	FlushFile(hFile);
	
	if (g_hDebug.BoolValue) {
		CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Соединение закрыто");
	}
	
	switch (hFileInfo.Get(FileInfo_iType)) {
		case DL_Index: {
			char sPath[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, sPath, sizeof(sPath), "%s/%s", CACHE_FOLDER, INDEX_FILE_NAME);
			ParseIndex(sPath);
			delete hFile;
		}
		
		case DL_Prefetch: {
			Recording iRecording = view_as<Recording>(hFileInfo.Get(FileInfo_aData));
			char sFilePath[PLATFORM_MAX_PATH];
			iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
			
			delete hFile;
			
			if (g_hDebug.BoolValue) {
				CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Загружено %d/%d байт", FileSize(sFilePath), iRecording.FileSize);
			}
			
			if (FileSize(sFilePath) == iRecording.FileSize) {
				iRecording.Downloading = 0;
			} else {
				DeleteFile(sFilePath);
				
				if (iRecording.Downloading++ < MAX_RETRIES) {
					FetchRecording(iRecording, true);
				}
			}
		}
		
		case DL_Play: {
			Recording iRecording = view_as<Recording>(hFileInfo.Get(FileInfo_aData));
			char sFilePath[PLATFORM_MAX_PATH];
			iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
			
			delete hFile;
			
			if (g_hDebug.BoolValue) {
				CPrintToChatAll("{green}[{lightgreen}jb{green}] {white}Загружено %d/%d байт", FileSize(sFilePath), iRecording.FileSize);
			}
			
			if (FileSize(sFilePath) == iRecording.FileSize) {
				iRecording.Downloading = 0;
				
				if (!(LoadRecording(iRecording) && PrepareBots(iRecording) && LoadFrames(iRecording))) {
					g_iClientInstruction = INST_NOP;
					doReturn();
					return 0;
				}
				
				SetPlaybackSpeedCOI();

				g_iClientInstruction |= INST_PLAY;
				g_iClientInstruction &= ~INST_WAIT;
			} else {
				DeleteFile(sFilePath);
				
				if (iRecording.Downloading++ < MAX_RETRIES) {
					FetchRecording(iRecording, false);
				} else {
					g_iClientInstruction = INST_NOP;
					doReturn();
				}
			}
		}
		
		case DL_Clean: {
			ArrayList hDirInfo = hFileInfo.Get(FileInfo_aData);
			
			StringMap hHash = hDirInfo.Get(0);
			
			char sBuffer[41];
			hFile.Seek(0, SEEK_SET);
			while (hFile.ReadLine(sBuffer, sizeof(sBuffer))) {
				hHash.SetString(sBuffer, NULL_STRING);
			}
			LogMessage("%T", "Downloaded Repo Hashes", LANG_SERVER, hHash.Size);
			
			CreateTimer(0.1, Timer_Cleanup, hDirInfo);
			
			delete hFile;
		}
	}
	
	delete hFileInfo;
	CloseHandle(hSocket);

	return 0;
}

void ParseIndex(char[] sPath) {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));
	
	KeyValues hKV = new KeyValues(sMapName);
	if (!hKV.ImportFromFile(sPath)) {
		return;
	}
	
	if (!hKV.GotoFirstSubKey()) {
		LogError("%T", "No Online Rec", LANG_SERVER, sMapName);
		return;
	}
	
	char sBuffer[64];
	char sFilePath[PLATFORM_MAX_PATH];
	float fPos[3], fAng[3];
	int i = 0;
	
	do {
		Recording iRecording = Recording.Instance();
		
		ClientInfo iClientInfo = ClientInfo.Instance();

		hKV.GetString("authorname", sBuffer, sizeof(sBuffer), NULL_STRING);
		iClientInfo.SetName(sBuffer);
		
		hKV.GetString("authorid", sBuffer, sizeof(sBuffer), NULL_STRING);
		iClientInfo.SetAuthID(sBuffer);

		hKV.GetString("date", sBuffer, sizeof(sBuffer), NULL_STRING);
		iRecording.Timestamp = StringToInt(sBuffer);
		
		hKV.GetString("hash", sBuffer, sizeof(sBuffer));
		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s", CACHE_FOLDER, sBuffer);
		iRecording.SetFilePath(sFilePath);
		
		iRecording.Repo = true;
		
		iRecording.FramesExpected = hKV.GetNum("frames");
		
		iClientInfo.Team = view_as<TFTeam>(hKV.GetNum("team"));
		iClientInfo.Class = view_as<TFClassType>(hKV.GetNum("class"));
		
		hKV.JumpToKey("origin");
		hKV.GotoFirstSubKey();
		fPos[0] = hKV.GetFloat("pos_x");
		fPos[1] = hKV.GetFloat("pos_y");
		fPos[2] = hKV.GetFloat("pos_z");
		fAng[0] = hKV.GetFloat("ang_p");
		fAng[1] = hKV.GetFloat("ang_y");
		iClientInfo.SetStartPos(fPos);
		iClientInfo.SetStartAng(fAng);
		hKV.GoBack();

		if (hKV.JumpToKey("equipment")) {
			hKV.GotoFirstSubKey();
			
			int iSlot = hKV.GetNum("slot");
			int iItemDefIdx = hKV.GetNum("itemdef", 0);
			switch (iItemDefIdx) {
				case 513, 730: {
					iRecording.SetEquipFilter(iSlot, iItemDefIdx);
				}
			}
			
			hKV.GoBack();
		}

		iRecording.ClientInfo.Push(iClientInfo);

		g_hRecordings.Push(iRecording);

		i++;
	} while (hKV.GotoNextKey());
	
	LogMessage("%T", "Loaded Repo", LANG_SERVER, i);
	
	delete hKV;

	CreateSpatialIndex();
}

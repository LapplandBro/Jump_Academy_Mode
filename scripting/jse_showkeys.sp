#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR	"AI"
#define PLUGIN_VERSION	"0.1.8"

#define UPDATE_URL		"http://jumpacademy.tf/plugins/jse/showkeys/updatefile.txt"

#include <clientprefs>
#include <multicolors>
#include <sourcemod>
#include <sdktools>
#include <smlib/clients>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <updater>

#define TEXT_HOLD_TIME 	0.5
#define TEXT_WAIT_FRAME	3

#define DEFAULT_COORD_X 0.58
#define DEFAULT_COORD_Y 0.40

#define DEFAULT_RGBA 255

enum Mode {
	DISPLAY,
	EDIT_COORDS,
	EDIT_COLORS
}

Handle g_hHudText;

Mode g_iMode[MAXPLAYERS + 1] = {DISPLAY, ...};
int g_iFocus[MAXPLAYERS + 1][2];

bool g_bEnabled[MAXPLAYERS + 1] =  { false, ... };
int g_iTarget[MAXPLAYERS + 1] =  { 0, ... };
float g_fHUDCoords[MAXPLAYERS + 1][2];
int g_iHUDColors[MAXPLAYERS + 1][4];
int g_iHUDColorsAlphaMultiplied[MAXPLAYERS + 1][3];

int g_iLastUpdate[MAXPLAYERS + 1][2];

Cookie g_hCookieEnabled;
Cookie g_hCookieCoords;
Cookie g_hCookieColor;

public Plugin myinfo = {
	name = "Jump Server Essentials - Show Keys",
	author = PLUGIN_AUTHOR,
	description = "JSE show keypresses module",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_showkeys_version", PLUGIN_VERSION, "Jump Server Essentials show keys version -- Do not modify",  FCVAR_NOTIFY | FCVAR_DONTRECORD);

	RegConsoleCmd("sm_showkeys", cmdShowKeys, "Toggle showing keypresses on HUD");
	RegConsoleCmd("sm_skeys", cmdShowKeys, "Toggle showing keypresses on HUD");

	RegConsoleCmd("sm_showkeys_options", cmdShowKeysOptions, "Change show keys HUD options");
	RegConsoleCmd("sm_skeys_options", cmdShowKeysOptions, "Change show keys HUD options");

	RegConsoleCmd("sm_showkeys_coords", cmdShowKeysCoords, "Change show keys HUD coordinates");
	RegConsoleCmd("sm_skeys_coords", cmdShowKeysCoords, "Change show keys HUD coordinates");

	RegConsoleCmd("sm_showkeys_colors", cmdShowKeysColors, "Change show keys HUD colors");
	RegConsoleCmd("sm_skeys_colors", cmdShowKeysColors, "Change show keys HUD colors");

	RegAdminCmd("sm_forceshowkeys", cmdForceShowKeys, ADMFLAG_GENERIC, "Force toggle showing keypresses on HUD");
	RegAdminCmd("sm_fskeys", cmdForceShowKeys, ADMFLAG_GENERIC, "Force toggle showing keypresses on HUD");

	HookEvent("player_spawn", Event_PlayerSpawn);

	// Cookies
	g_hCookieEnabled = new Cookie("jse_showkeys_enabled", "Переключить SKeys", CookieAccess_Private);
	g_hCookieCoords = new Cookie("jse_showkeys_coords", "Настройка HUD-а", CookieAccess_Private);
	g_hCookieColor = new Cookie("jse_showkeys_color", "Цвет SKeys в HUD-е", CookieAccess_Private);

	SetCookieMenuItem(CookieMenuHandler_Options, 0, "Показ нажатий");

	g_hHudText = CreateHudSynchronizer();

	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("jse_showkeys.phrases");

	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErrMax) {
	RegPluginLibrary("jse_showkeys");
	CreateNative("ForceShowKeys", Native_ForceShowKeys);
	CreateNative("ResetShowKeys", Native_ResetShowKeys);

	return APLRes_Success;
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && AreClientCookiesCached(i)) {
			OnClientCookiesCached(i);
		}
	}
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnClientCookiesCached(int iClient) {
	if (IsFakeClient(iClient)) {
		return;
	}

	if (!GetCookieBool(iClient, g_hCookieEnabled, g_bEnabled[iClient])) {
		g_bEnabled[iClient] = false;
	}

	if (!GetCookieFloat2D(iClient, g_hCookieCoords, g_fHUDCoords[iClient][0], g_fHUDCoords[iClient][1])) {
		g_fHUDCoords[iClient] =  view_as<float>({ DEFAULT_COORD_X, DEFAULT_COORD_Y });
	}

	if (GetCookieRGBA(iClient, g_hCookieColor, g_iHUDColors[iClient][0], g_iHUDColors[iClient][1], g_iHUDColors[iClient][2], g_iHUDColors[iClient][3])) {
		g_iHUDColorsAlphaMultiplied[iClient][0] = Math_Clamp(RoundToNearest(g_iHUDColors[iClient][0] * g_iHUDColors[iClient][3] / 255.0), 0, 255);
		g_iHUDColorsAlphaMultiplied[iClient][1] = Math_Clamp(RoundToNearest(g_iHUDColors[iClient][1] * g_iHUDColors[iClient][3] / 255.0), 0, 255);
		g_iHUDColorsAlphaMultiplied[iClient][2] = Math_Clamp(RoundToNearest(g_iHUDColors[iClient][2] * g_iHUDColors[iClient][3] / 255.0), 0, 255);
	} else {
		g_iHUDColors[iClient] =  { DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA };
		g_iHUDColorsAlphaMultiplied[iClient] =  { DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA };
	}

	g_iMode[iClient] = DISPLAY;
	g_iFocus[iClient] =  { 0, 0 };
	g_iTarget[iClient] = 0;

	g_iLastUpdate[iClient] =  { 0, 0 };
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAng[3], int &iWeapon, int &iSubType, int &iCmdNum, int &iTickCount, int &iSeed, int iMouse[2]) {
	if (!IsClientInGame(iClient)) {
		return Plugin_Continue;
	}

	switch (g_iMode[iClient]) {
		case DISPLAY: {
			if (!g_bEnabled[iClient]) {
				return Plugin_Continue;
			}

			int iObsTarget = iClient;
			int iBtns = iButtons;

			if (g_iTarget[iClient]) {
				if (IsClientInGame(g_iTarget[iClient])) {
					iObsTarget = g_iTarget[iClient];
					iBtns = GetClientButtons(iObsTarget);
				} else {
					g_iTarget[iClient] = 0;
				}
			} else if (TF2_GetClientTeam(iClient) == TFTeam_Spectator) {
				Obs_Mode iObserverMode = Client_GetObserverMode(iClient);
				if (iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE) {
					iObsTarget = Client_GetObserverTarget(iClient);
					if (!Client_IsValid(iObsTarget)) {
						return Plugin_Continue;
					}

					iBtns = GetClientButtons(iObsTarget);
				} else if (iObsTarget == iClient) {
					return Plugin_Continue;
				}
			}

			if (g_iLastUpdate[iObsTarget][1] == iButtons && (iTickCount - g_iLastUpdate[iObsTarget][0] < TEXT_WAIT_FRAME)) {
				return Plugin_Continue;
			}

			g_iLastUpdate[iObsTarget][1] = iButtons;
			g_iLastUpdate[iObsTarget][0] = iTickCount;

			if (iBtns & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_ATTACK | IN_ATTACK2 | IN_DUCK | IN_JUMP)) {
				char sM1[16], sM2[16];
				char sJump[16], sDuck[16];
				char sForward[4], sBack[4], sLeft[4], sRight[4];

				FormatEx(sForward,	sizeof(sForward),	iBtns & IN_FORWARD		? "W" : "\t\t\t");
				FormatEx(sBack,		sizeof(sBack),		iBtns & IN_BACK			? "S" : "\t");
				FormatEx(sLeft,		sizeof(sLeft),		iBtns & IN_MOVELEFT		? "A" : "\t\t");
				FormatEx(sRight,	sizeof(sRight),		iBtns & IN_MOVERIGHT	? "D" : "\t\t");

				FormatEx(sM1, sizeof(sM1), iBtns & IN_ATTACK  ? "%T" : "\t\t\t", "Mouse1", iClient);
				FormatEx(sM2, sizeof(sM2), iBtns & IN_ATTACK2 ? "%T" : "\t\t\t", "Mouse2", iClient);

				FormatEx(sJump, sizeof(sJump), iBtns & IN_JUMP? "%T" : NULL_STRING, "Jump", iClient);
				FormatEx(sDuck, sizeof(sDuck), iBtns & IN_DUCK? "%T" : NULL_STRING, "Duck", iClient);

				char sKeys[128];
				FormatEx(sKeys, sizeof(sKeys), "%10s%8s%s\n%8s%2s%2s%6s%s", sM1, sForward, sJump, sM2, sLeft, sBack, sRight, sDuck);

				SetHudTextParams(g_fHUDCoords[iClient][0] - 0.05, g_fHUDCoords[iClient][1], TEXT_HOLD_TIME, g_iHUDColorsAlphaMultiplied[iClient][0], g_iHUDColorsAlphaMultiplied[iClient][1], g_iHUDColorsAlphaMultiplied[iClient][2], 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(iClient, g_hHudText, sKeys);
			} else {
				SetHudTextParams(0.0, 0.0, 0.0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(iClient, g_hHudText, NULL_STRING);
			}
		}

		case EDIT_COORDS, EDIT_COLORS: {
			switch (g_iMode[iClient]) {
				case EDIT_COORDS: {
					g_fHUDCoords[iClient][0] = Math_Clamp(g_fHUDCoords[iClient][0] + 0.0005 * iMouse[0], 0.05, 0.9);
					g_fHUDCoords[iClient][1] = Math_Clamp(g_fHUDCoords[iClient][1] + 0.0005 * iMouse[1], 0.0, 1.0);

					if (iButtons & IN_ATTACK) {
						SetCookieFloat2D(iClient, g_hCookieCoords, g_fHUDCoords[iClient][0], g_fHUDCoords[iClient][1]);
						g_iMode[iClient] = DISPLAY;

						CreateTimer(0.2, Timer_Unfreeze, iClient);
					} else if (iButtons & IN_ATTACK2) {
						GetCookieFloat2D(iClient, g_hCookieCoords, g_fHUDCoords[iClient][0], g_fHUDCoords[iClient][1]);
						g_iMode[iClient] = DISPLAY;

						CreateTimer(0.2, Timer_Unfreeze, iClient);
					} else if (iButtons & IN_ATTACK3) {
						g_fHUDCoords[iClient] = view_as<float>({DEFAULT_COORD_X, DEFAULT_COORD_Y});

						SetCookieFloat2D(iClient, g_hCookieCoords, DEFAULT_COORD_X, DEFAULT_COORD_Y);
						g_iMode[iClient] = DISPLAY;

						CreateTimer(0.2, Timer_Unfreeze, iClient);
					}
				}

				case EDIT_COLORS: {
					static char sBuffer[254];
					static char sBar[4][64];

					g_iHUDColorsAlphaMultiplied[iClient][0] = Math_Clamp(RoundToNearest((g_iHUDColors[iClient][0] + 0.05 * iMouse[0]) * g_iHUDColors[iClient][3] / 255.0), 0, 255);
					g_iHUDColorsAlphaMultiplied[iClient][1] = Math_Clamp(RoundToNearest((g_iHUDColors[iClient][1] + 0.05 * iMouse[0]) * g_iHUDColors[iClient][3] / 255.0), 0, 255);
					g_iHUDColorsAlphaMultiplied[iClient][2] = Math_Clamp(RoundToNearest((g_iHUDColors[iClient][2] + 0.05 * iMouse[0]) * g_iHUDColors[iClient][3] / 255.0), 0, 255);

					g_iHUDColors[iClient][g_iFocus[iClient][0]] = Math_Clamp(RoundToNearest(g_iHUDColors[iClient][g_iFocus[iClient][0]] + 0.05 * iMouse[0]), 0, 255);


					for (int i = 0; i < 4; i++) {
						sBar[i][0] = '\0';

						int j = 0;
						for (j = 1; j <= RoundToFloor(float(g_iHUDColors[iClient][i])/8.0) && j <= 32; j++) {
							sBar[i][j-1] = '|';
						}
						sBar[i][j] = '\0';

					}

					Handle hMessage = StartMessageOne("KeyHintText", iClient);
					BfWriteByte(hMessage, 1);
					FormatEx(sBuffer, sizeof(sBuffer),	"%60s\n\n" ...
														"%sR: %02X  %s\n" ... 
														"%sG: %02X  %s\n" ... 
														"%sB: %02X  %s\n" ...
														"%sA: %02X  %s",
														"Show Keys Color",
														(g_iFocus[iClient][0] == 0 ? ">" : "  "), g_iHUDColors[iClient][0], sBar[0],
														(g_iFocus[iClient][0] == 1 ? ">" : "  "), g_iHUDColors[iClient][1], sBar[1],
														(g_iFocus[iClient][0] == 2 ? ">" : "  "), g_iHUDColors[iClient][2], sBar[2],
														(g_iFocus[iClient][0] == 3 ? ">" : "  "), g_iHUDColors[iClient][3], sBar[3]);

					BfWriteString(hMessage, sBuffer);
					EndMessage();

					if (iButtons & IN_ATTACK) {

						int iTick = GetGameTickCount();
						if (iTick - g_iFocus[iClient][1] > 10) {
							g_iFocus[iClient][0] = g_iFocus[iClient][0] + 1;

							if (g_iFocus[iClient][0] == 4) {
								SetCookieRGBA(iClient, g_hCookieColor, g_iHUDColors[iClient][0], g_iHUDColors[iClient][1], g_iHUDColors[iClient][2], g_iHUDColors[iClient][3]);
								g_iMode[iClient] = DISPLAY;

								CreateTimer(0.2, Timer_Unfreeze, iClient);
								hMessage = StartMessageOne("KeyHintText", iClient);
								BfWriteByte(hMessage, 1);
								BfWriteString(hMessage, " ");
								EndMessage();
							}


							g_iFocus[iClient][0] = g_iFocus[iClient][0] % 4;
							g_iFocus[iClient][1] = iTick;
						}
					} else if (iButtons & IN_ATTACK2) {
						int iTick = GetGameTickCount();
						if (iTick - g_iFocus[iClient][1] > 10) {
							g_iFocus[iClient][0] = Math_Min(g_iFocus[iClient][0] - 1, 0);
							g_iFocus[iClient][1] = iTick;
						}

					} else if (iButtons & IN_ATTACK3) {
						g_iHUDColors[iClient] =  { DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA };
						g_iHUDColorsAlphaMultiplied[iClient] =  { DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA };
						SetCookieRGBA(iClient, g_hCookieColor, DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA, DEFAULT_RGBA);

						g_iMode[iClient] = DISPLAY;

						CreateTimer(0.2, Timer_Unfreeze, iClient);
						hMessage = StartMessageOne("KeyHintText", iClient);
						BfWriteByte(hMessage, 1);
						BfWriteString(hMessage, " ");
						EndMessage();
					}
				}
			}


			char sM1[16], sM2[16];
			char sJump[16], sDuck[16];

			FormatEx(sM1, sizeof(sM1), "%T", "Mouse1", iClient);
			FormatEx(sM2, sizeof(sM2), "%T", "Mouse2", iClient);

			FormatEx(sJump, sizeof(sJump), "%T", "Jump", iClient);
			FormatEx(sDuck, sizeof(sDuck), "%T", "Duck", iClient);

			char sKeys[128];
			FormatEx(sKeys, sizeof(sKeys), "%10s%8s%s\n%8s%2s%2s%6s%s", sM1, "W", sJump, sM2, "A", "S", "D", sDuck);

			SetHudTextParams(g_fHUDCoords[iClient][0] - 0.05, g_fHUDCoords[iClient][1], TEXT_HOLD_TIME, g_iHUDColorsAlphaMultiplied[iClient][0], g_iHUDColorsAlphaMultiplied[iClient][1], g_iHUDColorsAlphaMultiplied[iClient][2], 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(iClient, g_hHudText, sKeys);
		}
	}

	return Plugin_Continue;
}

// Custom callbacks

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}

	g_iMode[iClient] = DISPLAY;

	return Plugin_Continue;
}

public Action Timer_Unfreeze(Handle hTimer, any aData) {
	SetEntityFlags(aData, GetEntityFlags(aData) & ~(FL_ATCONTROLS | FL_FROZEN));

	return Plugin_Handled;
}

// Natives
public int Native_ForceShowKeys(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	if (iClient >= 1 && iClient <= MaxClients) {
		g_iTarget[iClient] = GetNativeCell(2);
		g_bEnabled[iClient] = true;
	}

	return 0;
}

public int Native_ResetShowKeys(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	if (iClient >= 1 && iClient <= MaxClients) {
		if (!GetCookieBool(iClient, g_hCookieEnabled, g_bEnabled[iClient])) {
			g_bEnabled[iClient] = false;
		}

		g_iTarget[iClient] = 0;
	}

	return 0;
}

// Commands

public Action cmdShowKeys(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[Jump Essentials] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	if (iArgC == 0) {
		g_bEnabled[iClient] = !g_bEnabled[iClient];
		CPrintToChat(iClient, "{green}[{lightgreen}Jump Essentials{green}] {white}Показ нажатий %s.", g_bEnabled[iClient] ? "включен" : "выключен");
		g_iTarget[iClient] = 0;
	} else {
		char sArg1[64];
		GetCmdArg(1, sArg1, sizeof(sArg1));

		int iTarget = FindTarget(iClient, sArg1, false, false);
		if (iTarget != -1) {
			g_iTarget[iClient] = iTarget;
			g_bEnabled[iClient] = true;
			CPrintToChat(iClient, "{green}[{lightgreen}Jump Essentials{green}] {white}Показ нажатий включен для {limegreen}%N{white}.", iTarget);
		} else {
			g_bEnabled[iClient] = false;
		}
	}

	if (!g_bEnabled[iClient]) {
		g_iTarget[iClient] = 0;
	}

	g_hCookieEnabled.Set(iClient, g_bEnabled[iClient] ? "1" : "0");

	return Plugin_Handled;
}

public Action cmdShowKeysCoords(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[Jump Essentials] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	switch (g_iMode[iClient]) {
		case EDIT_COORDS: {
			g_iMode[iClient] = DISPLAY;
			SetEntityFlags(iClient, GetEntityFlags(iClient) & ~(FL_ATCONTROLS | FL_FROZEN));
		}
		case DISPLAY: {
			g_iMode[iClient] = EDIT_COORDS;
			SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_ATCONTROLS | FL_FROZEN);
		}
	}

	return Plugin_Handled;
}

public Action cmdShowKeysColors(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[Jump Essentials] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	switch (g_iMode[iClient]) {
		case EDIT_COLORS: {
			g_iMode[iClient] = DISPLAY;
			SetEntityFlags(iClient, GetEntityFlags(iClient) & ~(FL_ATCONTROLS | FL_FROZEN));
		}
		case DISPLAY: {
			g_iMode[iClient] = EDIT_COLORS;
			g_iFocus[iClient] =  { 0, 0 };

			SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_ATCONTROLS | FL_FROZEN);
		}
	}

	return Plugin_Handled;
}

public Action cmdShowKeysOptions(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[Jump Essentials] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	SendOptionsPanel(iClient);
	return Plugin_Handled;
}

public Action cmdForceShowKeys(int iClient, int iArgC) {
	if (iArgC != 2) {
		ReplyToCommand(iClient, "[Jump Essentials] Usage: sm_forceshowkeys <target> <0/1>");
		return Plugin_Handled;
	}

	char sArg1[64];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sArg2[64];
	GetCmdArg(2, sArg2, sizeof(sArg2));

	bool bEnabled = StringToInt(sArg2) != 0;

	int iTarget = FindTarget(iClient, sArg1, false, false);
	if (iTarget != -1) {
		g_iTarget[iTarget] = 0;
		g_bEnabled[iTarget] = bEnabled;

		CPrintToChat(iTarget, "{green}[{lightgreen}Jump Essentials{green}] {white}Показ кнопок %s.", bEnabled ? "enabled" : "disabled");
		CPrintToChat(iClient, "{green}[{lightgreen}Jump Essentials{green}] {white}Показ кнопок %s для {limegreen}%N{white}.", bEnabled ? "включен" : "выключен", iTarget);

		g_hCookieEnabled.Set(iTarget, bEnabled ? "1" : "0");
	}

	return Plugin_Handled;
}

// Stock

stock bool GetCookieBool(int iClient, Cookie hCookie, bool &bValue) {
	char sBuffer[8];
	hCookie.Get(iClient, sBuffer, sizeof(sBuffer));

	if (sBuffer[0]) {
		bValue = StringToInt(sBuffer) != 0;
		return true;
	}

	return false;
}

stock bool GetCookieFloat2D(int iClient, Cookie hCookie, float &fValueA, float &fValueB) {
	char sBuffer[64];
	hCookie.Get(iClient, sBuffer, sizeof(sBuffer));

	char sFloatBuffers[2][64];
	if (ExplodeString(sBuffer, " ", sFloatBuffers, sizeof(sFloatBuffers), sizeof(sFloatBuffers[]), false) != 2) {
		return false;
	}

	fValueA = StringToFloat(sFloatBuffers[0]);
	fValueB = StringToFloat(sFloatBuffers[1]);

	return true;
}

stock bool GetCookieRGBA(int iClient, Cookie hCookie, int &iValueA, int &iValueB, int &iValueC, int &iValueD) {
	char sBuffer[64];
	hCookie.Get(iClient, sBuffer, sizeof(sBuffer));

	if (strlen(sBuffer) != 8) {
		return false;
	}

	int iColor = StringToInt(sBuffer, 16);

	iValueA = (iColor >> 24) & 0xFF;
	iValueB = (iColor >> 16) & 0xFF;
	iValueC = (iColor >>  8) & 0xFF;
	iValueD = (iColor      ) & 0xFF;

	return true;
}

stock void SetCookieFloat2D(int iClient, Cookie hCookie, float fValueA, float fValueB) {
	char sBuffer[64];
	FormatEx(sBuffer, sizeof(sBuffer), "%.4f %.4f", fValueA, fValueB);

	hCookie.Set(iClient, sBuffer);
}

stock void SetCookieRGBA(int iClient, Cookie hCookie, int iValueA, int iValueB, int iValueC, int iValueD) {
	char sBuffer[9];
	FormatEx(sBuffer, sizeof(sBuffer), "%02X%02X%02X%02X", iValueA & 0xFF, iValueB & 0xFF, iValueC & 0xFF, iValueD & 0xFF);

	hCookie.Set(iClient, sBuffer);
}

// Menus

public void CookieMenuHandler_Options(int iClient, CookieMenuAction iAction, any aInfo, char[] sBuffer, int iMaxLength) {
	if (iAction == CookieMenuAction_SelectOption) {
		SendOptionsPanel(iClient);
	}
}

void SendOptionsPanel(int iClient) {
	Menu hMenu = new Menu(MenuHandler_Options);
	hMenu.SetTitle("Настройки показа нажатий");

	hMenu.AddItem(NULL_STRING, "Передвинуть в HUD-е");
	hMenu.AddItem(NULL_STRING, "Перекрасить");

	hMenu.Display(iClient, 0);
}

public int MenuHandler_Options(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			switch (iOption) {
				case 0: {
					// Move
					FakeClientCommand(iClient, "sm_showkeys_coords");
				}
				case 1: {
					// Recolor
					FakeClientCommand(iClient, "sm_showkeys_colors");
				}
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}

	}

	return 0;
}

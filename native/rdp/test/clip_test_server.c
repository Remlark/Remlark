/*
 * 剪贴板测试服务端（仅用于端到端测试，不随应用打包）。
 * 基于 FreeRDP 服务端 API，只实现 cliprdr 通道，按固定剧本与客户端交互，并把结果按行输出到 stdout：
 *   1. 客户端发出首个格式列表后，服务端声明文本，客户端读取后应收到 "server-text-你好"
 *   2. 客户端声明文本 -> 服务端读取并输出 "CLIENT_TEXT:<文本>"
 *   3. 客户端声明文件 -> 服务端读取文件列表与第一个文件内容，输出 "CLIENT_FILES:<名称>" 与 "CLIENT_FILE_DATA:<内容>"
 *   4. 之后服务端声明文件（folder\a.txt=alpha、b.txt=bravo），客户端应下载到本地
 * 用法：clip_test_server <port> <cert> <key>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/freerdp.h>
#include <freerdp/listener.h>
#include <freerdp/channels/channels.h>
#include <freerdp/channels/wtsvc.h>
#include <freerdp/channels/cliprdr.h>
#include <freerdp/server/cliprdr.h>
#include <freerdp/utils/cliprdr_utils.h>
#include <freerdp/crypto/certificate.h>
#include <freerdp/crypto/privatekey.h>
#include <winpr/shell.h>
#include <winpr/string.h>
#include <winpr/user.h>

#define FILEDESC_ID 0xC0F0

static const char* g_cert;
static const char* g_key;

typedef struct
{
	rdpContext ctx;
	HANDLE vcm;
	CliprdrServerContext* clip;
	int step;
	UINT32 client_filedesc_id;
	UINT32 requested;
	FILEDESCRIPTORW* client_files;
	UINT32 client_file_count;
} PeerCtx;

static void out(const char* fmt, const char* s)
{
	printf(fmt, s);
	printf("\n");
	fflush(stdout);
}

static void send_format_list(CliprdrServerContext* clip, UINT32 id, const char* name)
{
	CLIPRDR_FORMAT f = { 0 };
	f.formatId = id;
	f.formatName = (char*)name;
	CLIPRDR_FORMAT_LIST list = { 0 };
	list.common.msgType = CB_FORMAT_LIST;
	list.numFormats = 1;
	list.formats = &f;
	(void)clip->ServerFormatList(clip, &list);
}

static void request(PeerCtx* p, UINT32 id)
{
	CLIPRDR_FORMAT_DATA_REQUEST r = { 0 };
	r.common.msgType = CB_FORMAT_DATA_REQUEST;
	r.requestedFormatId = id;
	p->requested = id;
	(void)p->clip->ServerFormatDataRequest(p->clip, &r);
}

static void request_contents(PeerCtx* p, UINT32 index, UINT32 flags, UINT32 len)
{
	CLIPRDR_FILE_CONTENTS_REQUEST r = { 0 };
	r.common.msgType = CB_FILECONTENTS_REQUEST;
	r.streamId = 1;
	r.listIndex = index;
	r.dwFlags = flags;
	r.cbRequested = len;
	(void)p->clip->ServerFileContentsRequest(p->clip, &r);
}

/* 服务端提供的文件 */
static const char* g_names[] = { "folder", "folder\\a.txt", "b.txt" };
static const char* g_data[] = { NULL, "alpha", "bravo" };

static UINT on_client_caps(CliprdrServerContext* c, const CLIPRDR_CAPABILITIES* caps)
{
	WINPR_UNUSED(c);
	WINPR_UNUSED(caps);
	return CHANNEL_RC_OK;
}

static UINT on_client_format_list(CliprdrServerContext* c, const CLIPRDR_FORMAT_LIST* list)
{
	PeerCtx* p = (PeerCtx*)c->custom;
	CLIPRDR_FORMAT_LIST_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_LIST_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	(void)c->ServerFormatListResponse(c, &resp);

	BOOL text = FALSE;
	p->client_filedesc_id = 0;
	for (UINT32 i = 0; i < list->numFormats; i++)
	{
		if (list->formats[i].formatId == CF_UNICODETEXT)
			text = TRUE;
		if (list->formats[i].formatName && strcmp(list->formats[i].formatName, "FileGroupDescriptorW") == 0)
			p->client_filedesc_id = list->formats[i].formatId;
	}
	if (p->step == 0)
	{
		/* 首个格式列表：服务端声明文本 */
		p->step = 1;
		out("%s", "READY");
		send_format_list(c, CF_UNICODETEXT, NULL);
		return CHANNEL_RC_OK;
	}
	if (p->client_filedesc_id)
		request(p, p->client_filedesc_id);
	else if (text)
		request(p, CF_UNICODETEXT);
	return CHANNEL_RC_OK;
}

static UINT on_client_data_request(CliprdrServerContext* c, const CLIPRDR_FORMAT_DATA_REQUEST* req)
{
	CLIPRDR_FORMAT_DATA_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	if (req->requestedFormatId == CF_UNICODETEXT)
	{
		size_t len = 0;
		WCHAR* w = ConvertUtf8ToWCharAlloc("server-text-你好", &len);
		resp.common.dataLen = (UINT32)((len + 1) * sizeof(WCHAR));
		resp.requestedFormatData = (const BYTE*)w;
		(void)c->ServerFormatDataResponse(c, &resp);
		free(w);
	}
	else if (req->requestedFormatId == FILEDESC_ID)
	{
		FILEDESCRIPTORW d[3] = { 0 };
		for (int i = 0; i < 3; i++)
		{
			d[i].dwFlags = FD_ATTRIBUTES | FD_FILESIZE;
			d[i].dwFileAttributes = g_data[i] ? FILE_ATTRIBUTE_NORMAL : FILE_ATTRIBUTE_DIRECTORY;
			d[i].nFileSizeLow = g_data[i] ? (UINT32)strlen(g_data[i]) : 0;
			(void)ConvertUtf8ToWChar(g_names[i], d[i].cFileName, ARRAYSIZE(d[i].cFileName));
		}
		BYTE* data = NULL;
		UINT32 len = 0;
		(void)cliprdr_serialize_file_list(d, 3, &data, &len);
		resp.common.dataLen = len;
		resp.requestedFormatData = data;
		(void)c->ServerFormatDataResponse(c, &resp);
		free(data);
	}
	else
	{
		resp.common.msgFlags = CB_RESPONSE_FAIL;
		(void)c->ServerFormatDataResponse(c, &resp);
	}
	return CHANNEL_RC_OK;
}

static UINT on_client_data_response(CliprdrServerContext* c, const CLIPRDR_FORMAT_DATA_RESPONSE* resp)
{
	PeerCtx* p = (PeerCtx*)c->custom;
	if (resp->common.msgFlags & CB_RESPONSE_FAIL)
	{
		out("%s", "CLIENT_FAIL");
		return CHANNEL_RC_OK;
	}
	if (p->requested == CF_UNICODETEXT)
	{
		char* s = ConvertWCharNToUtf8Alloc((const WCHAR*)resp->requestedFormatData,
		                                   resp->common.dataLen / sizeof(WCHAR), NULL);
		out("CLIENT_TEXT:%s", s ? s : "");
		free(s);
	}
	else if (p->requested == p->client_filedesc_id)
	{
		free(p->client_files);
		p->client_files = NULL;
		if (cliprdr_parse_file_list(resp->requestedFormatData, resp->common.dataLen, &p->client_files,
		                            &p->client_file_count) != CHANNEL_RC_OK)
			return CHANNEL_RC_OK;
		char names[2048] = { 0 };
		for (UINT32 i = 0; i < p->client_file_count; i++)
		{
			char* n = ConvertWCharNToUtf8Alloc(p->client_files[i].cFileName, 260, NULL);
			if (i)
				strcat(names, "|");
			strncat(names, n ? n : "", sizeof(names) - strlen(names) - 1);
			free(n);
		}
		out("CLIENT_FILES:%s", names);
		/* 读取第一个普通文件：先取大小，再取内容 */
		for (UINT32 i = 0; i < p->client_file_count; i++)
		{
			if (!(p->client_files[i].dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
			{
				request_contents(p, i, FILECONTENTS_SIZE, 8);
				break;
			}
		}
	}
	return CHANNEL_RC_OK;
}

static UINT on_client_contents_request(CliprdrServerContext* c, const CLIPRDR_FILE_CONTENTS_REQUEST* req)
{
	CLIPRDR_FILE_CONTENTS_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FILECONTENTS_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	resp.streamId = req->streamId;
	const char* d = req->listIndex < 3 ? g_data[req->listIndex] : NULL;
	BYTE size[8] = { 0 };
	if (!d)
		resp.common.msgFlags = CB_RESPONSE_FAIL;
	else if (req->dwFlags & FILECONTENTS_SIZE)
	{
		size[0] = (BYTE)strlen(d);
		resp.cbRequested = 8;
		resp.requestedData = size;
	}
	else
	{
		const UINT32 len = (UINT32)strlen(d);
		const UINT32 off = req->nPositionLow;
		const UINT32 n = off >= len ? 0 : (len - off < req->cbRequested ? len - off : req->cbRequested);
		resp.cbRequested = n;
		resp.requestedData = (const BYTE*)d + off;
	}
	(void)c->ServerFileContentsResponse(c, &resp);
	return CHANNEL_RC_OK;
}

static UINT on_client_contents_response(CliprdrServerContext* c, const CLIPRDR_FILE_CONTENTS_RESPONSE* resp)
{
	PeerCtx* p = (PeerCtx*)c->custom;
	if (resp->common.msgFlags & CB_RESPONSE_FAIL)
	{
		out("%s", "CLIENT_FILE_FAIL");
		return CHANNEL_RC_OK;
	}
	if (resp->cbRequested == 8 && p->step == 1)
	{
		/* 收到大小，接着请求内容 */
		UINT64 sz = 0;
		for (int i = 7; i >= 0; i--)
			sz = (sz << 8) | resp->requestedData[i];
		p->step = 2;
		for (UINT32 i = 0; i < p->client_file_count; i++)
		{
			if (!(p->client_files[i].dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
			{
				request_contents(p, i, FILECONTENTS_RANGE, (UINT32)sz);
				break;
			}
		}
		return CHANNEL_RC_OK;
	}
	char buf[1024] = { 0 };
	memcpy(buf, resp->requestedData, resp->cbRequested < 1023 ? resp->cbRequested : 1023);
	out("CLIENT_FILE_DATA:%s", buf);
	/* 最后由服务端声明文件，供客户端下载 */
	p->step = 3;
	send_format_list(c, FILEDESC_ID, "FileGroupDescriptorW");
	return CHANNEL_RC_OK;
}

static UINT on_simple(CliprdrServerContext* c, const void* x)
{
	WINPR_UNUSED(c);
	WINPR_UNUSED(x);
	return CHANNEL_RC_OK;
}

static BOOL peer_context_new(freerdp_peer* client, rdpContext* ctx)
{
	PeerCtx* p = (PeerCtx*)ctx;
	p->vcm = WTSOpenServerA((LPSTR)client->context);
	return p->vcm && p->vcm != INVALID_HANDLE_VALUE;
}

static void peer_context_free(freerdp_peer* client, rdpContext* ctx)
{
	WINPR_UNUSED(client);
	PeerCtx* p = (PeerCtx*)ctx;
	if (p->clip)
	{
		p->clip->Stop(p->clip);
		cliprdr_server_context_free(p->clip);
	}
	free(p->client_files);
	WTSCloseServer(p->vcm);
}

static BOOL peer_post_connect(freerdp_peer* client)
{
	PeerCtx* p = (PeerCtx*)client->context;
	if (!WTSVirtualChannelManagerIsChannelJoined(p->vcm, CLIPRDR_SVC_CHANNEL_NAME))
	{
		out("%s", "NO_CLIPRDR");
		return TRUE;
	}
	CliprdrServerContext* c = cliprdr_server_context_new(p->vcm);
	if (!c)
		return FALSE;
	c->rdpcontext = client->context;
	c->custom = p;
	c->useLongFormatNames = TRUE;
	c->streamFileClipEnabled = TRUE;
	c->fileClipNoFilePaths = TRUE;
	c->ClientCapabilities = on_client_caps;
	c->ClientFormatList = on_client_format_list;
	c->ClientFormatListResponse = (psCliprdrClientFormatListResponse)on_simple;
	c->ClientLockClipboardData = (psCliprdrClientLockClipboardData)on_simple;
	c->ClientUnlockClipboardData = (psCliprdrClientUnlockClipboardData)on_simple;
	c->ClientFormatDataRequest = on_client_data_request;
	c->ClientFormatDataResponse = on_client_data_response;
	c->ClientFileContentsRequest = on_client_contents_request;
	c->ClientFileContentsResponse = on_client_contents_response;
	p->clip = c;
	return c->Start(c) == CHANNEL_RC_OK;
}

static BOOL peer_activate(freerdp_peer* client)
{
	WINPR_UNUSED(client);
	return TRUE;
}

static DWORD WINAPI peer_main(LPVOID arg)
{
	freerdp_peer* client = (freerdp_peer*)arg;
	client->ContextSize = sizeof(PeerCtx);
	client->ContextNew = peer_context_new;
	client->ContextFree = peer_context_free;
	if (!freerdp_peer_context_new(client))
		return 0;
	rdpSettings* s = client->context->settings;
	rdpPrivateKey* key = freerdp_key_new_from_file_enc(g_key, NULL);
	rdpCertificate* cert = freerdp_certificate_new_from_file(g_cert);
	if (!key || !cert || !freerdp_settings_set_pointer_len(s, FreeRDP_RdpServerRsaKey, key, 1) ||
	    !freerdp_settings_set_pointer_len(s, FreeRDP_RdpServerCertificate, cert, 1) ||
	    !freerdp_settings_set_bool(s, FreeRDP_TlsSecurity, TRUE) ||
	    !freerdp_settings_set_bool(s, FreeRDP_NlaSecurity, FALSE) ||
	    !freerdp_settings_set_bool(s, FreeRDP_ExtSecurity, FALSE) ||
	    !freerdp_settings_set_bool(s, FreeRDP_RdpSecurity, FALSE) ||
	    !freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, 32))
		return 0;
	client->PostConnect = peer_post_connect;
	client->Activate = peer_activate;
	if (!client->Initialize(client))
		return 0;
	PeerCtx* p = (PeerCtx*)client->context;
	while (TRUE)
	{
		HANDLE handles[MAXIMUM_WAIT_OBJECTS] = { 0 };
		DWORD count = client->GetEventHandles(client, handles, 32);
		if (count == 0)
			break;
		handles[count++] = WTSVirtualChannelManagerGetEventHandle(p->vcm);
		if (WaitForMultipleObjects(count, handles, FALSE, INFINITE) == WAIT_FAILED)
			break;
		if (!client->CheckFileDescriptor(client))
			break;
		if (!WTSVirtualChannelManagerCheckFileDescriptor(p->vcm))
			break;
	}
	client->Disconnect(client);
	freerdp_peer_context_free(client);
	freerdp_peer_free(client);
	return 0;
}

static BOOL on_peer(freerdp_listener* listener, freerdp_peer* client)
{
	WINPR_UNUSED(listener);
	HANDLE t = CreateThread(NULL, 0, peer_main, client, 0, NULL);
	if (!t)
		return FALSE;
	CloseHandle(t);
	return TRUE;
}

int main(int argc, char** argv)
{
	if (argc < 4)
	{
		fprintf(stderr, "usage: %s <port> <cert> <key>\n", argv[0]);
		return 1;
	}
	g_cert = argv[2];
	g_key = argv[3];
	WTSRegisterWtsApiFunctionTable(FreeRDP_InitWtsApi());
	freerdp_listener* l = freerdp_listener_new();
	l->PeerAccepted = on_peer;
	if (!l->Open(l, "127.0.0.1", (UINT16)atoi(argv[1])))
		return 2;
	out("%s", "LISTENING");
	while (TRUE)
	{
		HANDLE handles[32] = { 0 };
		DWORD count = l->GetEventHandles(l, handles, 32);
		if (count == 0 || WaitForMultipleObjects(count, handles, FALSE, INFINITE) == WAIT_FAILED)
			break;
		if (!l->CheckFileDescriptor(l))
			break;
	}
	freerdp_listener_free(l);
	return 0;
}

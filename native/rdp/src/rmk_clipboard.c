/*
 * Remlark RDP 剪贴板（cliprdr 通道）：
 * - 文本：本地 <-> 远程双向（CF_UNICODETEXT）
 * - 本地文件 -> 远程：声明 FileGroupDescriptorW，远程粘贴时按需读取本地文件内容
 * - 远程文件 -> 本地：远程复制文件后下载到临时目录，完成后通知 Dart 写入本地剪贴板
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#if defined(_WIN32)
#include <windows.h>
#include <direct.h>
#define RMK_SEP '\\'
#define rmk_mkdir(p) _mkdir(p)
#define rmk_fseek _fseeki64
#else
#include <dirent.h>
#include <unistd.h>
#define RMK_SEP '/'
#define rmk_mkdir(p) mkdir(p, 0755)
#define rmk_fseek fseeko
#endif

#include <freerdp/channels/cliprdr.h>
#include <freerdp/utils/cliprdr_utils.h>
#include <winpr/shell.h>
#include <winpr/string.h>
#include <winpr/sysinfo.h>
#include <winpr/user.h>

#include "rmk_internal.h"

/* 本客户端为文件列表格式分配的格式 id */
#define RMK_FILEDESC_ID 0xC0BC
#define RMK_FILECONTENTS_ID 0xC0BD
#define RMK_FILEDESC_NAME "FileGroupDescriptorW"
#define RMK_FILECONTENTS_NAME "FileContents"

/* 远程文件下载上限与分块大小 */
#define RMK_MAX_DOWNLOAD (2ULL * 1024 * 1024 * 1024)
#define RMK_CHUNK (512u * 1024u)

typedef enum
{
	RMK_LOCAL_NONE = 0,
	RMK_LOCAL_TEXT = 1,
	RMK_LOCAL_FILES = 2
} RmkLocalKind;

/* 本地文件条目 */
typedef struct
{
	char* path;
	FILEDESCRIPTORW desc;
	UINT64 size;
} RmkLocalFile;

struct rmk_clip
{
	RmkRdp* rdp;
	CliprdrClientContext* ctx;
	CRITICAL_SECTION lock;
	UINT32 server_flags;

	/* 本地剪贴板内容 */
	RmkLocalKind kind;
	WCHAR* text;
	size_t text_bytes;
	RmkLocalFile* files;
	UINT32 file_count;
	UINT32 file_capacity;
	FILE* serve_fp;
	UINT32 serve_index;

	/* 远程剪贴板 */
	UINT32 requested_format;
	UINT32 remote_filedesc_id;

	/* 远程文件下载 */
	FILEDESCRIPTORW* dl_files;
	UINT32 dl_count;
	UINT32 dl_index;
	UINT64 dl_offset;
	UINT64 dl_size;
	UINT64 dl_done;
	UINT64 dl_total;
	FILE* dl_fp;
	char* dl_root;
	UINT32 dl_stream;
	UINT64 dl_last_report;
};

/* ---------- 工具 ---------- */

static UINT64 rmk_desc_size(const FILEDESCRIPTORW* d)
{
	return ((UINT64)d->nFileSizeHigh << 32) | d->nFileSizeLow;
}

static BOOL rmk_desc_is_dir(const FILEDESCRIPTORW* d)
{
	return (d->dwFlags & FD_ATTRIBUTES) && (d->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY);
}

/* 逐级创建目录 */
static void rmk_mkdirs(const char* path)
{
	char* tmp = _strdup(path);
	if (!tmp)
		return;
	for (char* p = tmp + 1; *p; p++)
	{
		if (*p == '/' || *p == '\\')
		{
			const char c = *p;
			*p = '\0';
			rmk_mkdir(tmp);
			*p = c;
		}
	}
	rmk_mkdir(tmp);
	free(tmp);
}

/* 远程相对路径（\ 分隔）转本地路径，去掉 .. 等危险片段 */
static char* rmk_local_path(const char* root, const WCHAR* wname)
{
	char* name = ConvertWCharNToUtf8Alloc(wname, 260, NULL);
	if (!name)
		return NULL;
	const size_t len = strlen(root) + strlen(name) + 2;
	char* out = calloc(1, len);
	if (!out)
	{
		free(name);
		return NULL;
	}
	strcpy(out, root);
	size_t pos = strlen(out);
	out[pos++] = RMK_SEP;
	char* save = NULL;
	BOOL first = TRUE;
	for (char* tok = strtok_s(name, "\\/", &save); tok; tok = strtok_s(NULL, "\\/", &save))
	{
		if (strcmp(tok, "..") == 0 || strcmp(tok, ".") == 0 || strchr(tok, ':'))
			continue;
		if (!first)
			out[pos++] = RMK_SEP;
		strcpy(out + pos, tok);
		pos += strlen(tok);
		first = FALSE;
	}
	free(name);
	return out;
}

/* ---------- 发送 ---------- */

/* 向远程声明当前本地剪贴板格式 */
static void rmk_send_format_list(RmkClipboard* clip)
{
	if (!clip->ctx)
		return;
	CLIPRDR_FORMAT formats[2] = { 0 };
	CLIPRDR_FORMAT_LIST list = { 0 };
	list.common.msgType = CB_FORMAT_LIST;
	if (clip->kind == RMK_LOCAL_TEXT)
	{
		formats[0].formatId = CF_UNICODETEXT;
		list.numFormats = 1;
	}
	else if (clip->kind == RMK_LOCAL_FILES)
	{
		formats[0].formatId = RMK_FILEDESC_ID;
		formats[0].formatName = RMK_FILEDESC_NAME;
		formats[1].formatId = RMK_FILECONTENTS_ID;
		formats[1].formatName = RMK_FILECONTENTS_NAME;
		list.numFormats = 2;
	}
	list.formats = formats;
	(void)clip->ctx->ClientFormatList(clip->ctx, &list);
}

static void rmk_send_data_response(RmkClipboard* clip, const BYTE* data, UINT32 len, BOOL ok)
{
	CLIPRDR_FORMAT_DATA_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
	resp.common.msgFlags = ok ? CB_RESPONSE_OK : CB_RESPONSE_FAIL;
	resp.common.dataLen = ok ? len : 0;
	resp.requestedFormatData = ok ? data : NULL;
	(void)clip->ctx->ClientFormatDataResponse(clip->ctx, &resp);
}

static void rmk_send_contents_response(RmkClipboard* clip, UINT32 stream, const BYTE* data,
                                       UINT32 len, BOOL ok)
{
	CLIPRDR_FILE_CONTENTS_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FILECONTENTS_RESPONSE;
	resp.common.msgFlags = ok ? CB_RESPONSE_OK : CB_RESPONSE_FAIL;
	resp.streamId = stream;
	resp.cbRequested = ok ? len : 0;
	resp.requestedData = ok ? data : NULL;
	(void)clip->ctx->ClientFileContentsResponse(clip->ctx, &resp);
}

static void rmk_request_format(RmkClipboard* clip, UINT32 format)
{
	CLIPRDR_FORMAT_DATA_REQUEST req = { 0 };
	req.common.msgType = CB_FORMAT_DATA_REQUEST;
	req.requestedFormatId = format;
	clip->requested_format = format;
	(void)clip->ctx->ClientFormatDataRequest(clip->ctx, &req);
}

/* ---------- 远程文件下载 ---------- */

static void rmk_download_reset(RmkClipboard* clip)
{
	if (clip->dl_fp)
		fclose(clip->dl_fp);
	clip->dl_fp = NULL;
	free(clip->dl_files);
	clip->dl_files = NULL;
	clip->dl_count = clip->dl_index = 0;
	free(clip->dl_root);
	clip->dl_root = NULL;
}

/* 下载完成：通知 Dart 顶层文件 / 目录路径 */
static void rmk_download_finish(RmkClipboard* clip)
{
	size_t cap = 1024, len = 0;
	char* out = calloc(1, cap);
	for (UINT32 i = 0; out && i < clip->dl_count; i++)
	{
		const FILEDESCRIPTORW* d = &clip->dl_files[i];
		BOOL top = TRUE;
		for (size_t k = 0; k < 260 && d->cFileName[k]; k++)
			if (d->cFileName[k] == '\\' || d->cFileName[k] == '/')
				top = FALSE;
		if (!top)
			continue;
		char* p = rmk_local_path(clip->dl_root, d->cFileName);
		if (!p)
			continue;
		const size_t n = strlen(p);
		if (len + n + 2 > cap)
		{
			cap = (len + n + 2) * 2;
			char* grown = realloc(out, cap);
			if (!grown)
			{
				free(p);
				break;
			}
			out = grown;
		}
		if (len)
			out[len++] = '\n';
		memcpy(out + len, p, n);
		len += n;
		out[len] = '\0';
		free(p);
	}
	if (out && len)
		rmk_emit(clip->rdp, RMK_EV_CLIP_FILES, (int32_t)clip->dl_count, 0, 0, 0, out);
	free(out);
	rmk_download_reset(clip);
}

/* 请求当前文件的下一块数据；当前文件完成后转到下一个文件 */
static void rmk_download_next(RmkClipboard* clip)
{
	while (clip->dl_index < clip->dl_count)
	{
		const FILEDESCRIPTORW* d = &clip->dl_files[clip->dl_index];
		if (!clip->dl_fp)
		{
			char* path = rmk_local_path(clip->dl_root, d->cFileName);
			if (!path)
			{
				clip->dl_index++;
				continue;
			}
			if (rmk_desc_is_dir(d))
			{
				rmk_mkdirs(path);
				free(path);
				clip->dl_index++;
				continue;
			}
			/* 创建父目录 */
			char* slash = strrchr(path, RMK_SEP);
			if (slash)
			{
				*slash = '\0';
				rmk_mkdirs(path);
				*slash = RMK_SEP;
			}
			clip->dl_fp = fopen(path, "wb");
			free(path);
			clip->dl_offset = 0;
			clip->dl_size = rmk_desc_size(d);
			if (!clip->dl_fp || clip->dl_size == 0)
			{
				if (clip->dl_fp)
					fclose(clip->dl_fp);
				clip->dl_fp = NULL;
				clip->dl_index++;
				continue;
			}
		}
		const UINT64 remain = clip->dl_size - clip->dl_offset;
		CLIPRDR_FILE_CONTENTS_REQUEST req = { 0 };
		req.common.msgType = CB_FILECONTENTS_REQUEST;
		req.streamId = ++clip->dl_stream;
		req.listIndex = clip->dl_index;
		req.dwFlags = FILECONTENTS_RANGE;
		req.nPositionLow = (UINT32)(clip->dl_offset & 0xFFFFFFFF);
		req.nPositionHigh = (UINT32)(clip->dl_offset >> 32);
		req.cbRequested = (UINT32)(remain < RMK_CHUNK ? remain : RMK_CHUNK);
		(void)clip->ctx->ClientFileContentsRequest(clip->ctx, &req);
		return;
	}
	rmk_download_finish(clip);
}

/* 收到远程文件列表：检查大小后开始下载 */
static void rmk_download_start(RmkClipboard* clip, const BYTE* data, UINT32 len)
{
	rmk_download_reset(clip);
	if (!clip->rdp->temp_dir)
		return;
	if (cliprdr_parse_file_list(data, len, &clip->dl_files, &clip->dl_count) != CHANNEL_RC_OK ||
	    clip->dl_count == 0)
	{
		rmk_download_reset(clip);
		return;
	}
	clip->dl_total = 0;
	for (UINT32 i = 0; i < clip->dl_count; i++)
		clip->dl_total += rmk_desc_size(&clip->dl_files[i]);
	if (clip->dl_total > RMK_MAX_DOWNLOAD)
	{
		rmk_emit(clip->rdp, RMK_EV_CLIP_FILES_SKIPPED, (int32_t)clip->dl_count,
		         (int32_t)(clip->dl_total / (1024 * 1024)), 0, 0, NULL);
		rmk_download_reset(clip);
		return;
	}
	char root[1024];
	sprintf_s(root, sizeof(root), "%s%cremlark-clip-%" PRIu64, clip->rdp->temp_dir, RMK_SEP,
	          GetTickCount64());
	clip->dl_root = _strdup(root);
	rmk_mkdirs(root);
	clip->dl_done = 0;
	clip->dl_last_report = 0;
	rmk_download_next(clip);
}

/* ---------- 本地文件 ---------- */

static void rmk_files_clear(RmkClipboard* clip)
{
	for (UINT32 i = 0; i < clip->file_count; i++)
		free(clip->files[i].path);
	free(clip->files);
	clip->files = NULL;
	clip->file_count = clip->file_capacity = 0;
	if (clip->serve_fp)
		fclose(clip->serve_fp);
	clip->serve_fp = NULL;
}

/* 添加一个本地条目，rel 为远程看到的相对路径（\ 分隔） */
static void rmk_files_add(RmkClipboard* clip, const char* path, const char* rel, BOOL dir,
                          UINT64 size)
{
	if (clip->file_count == clip->file_capacity)
	{
		const UINT32 cap = clip->file_capacity ? clip->file_capacity * 2 : 16;
		RmkLocalFile* grown = realloc(clip->files, sizeof(RmkLocalFile) * cap);
		if (!grown)
			return;
		clip->files = grown;
		clip->file_capacity = cap;
	}
	RmkLocalFile* f = &clip->files[clip->file_count];
	memset(f, 0, sizeof(*f));
	f->path = _strdup(path);
	f->size = dir ? 0 : size;
	f->desc.dwFlags = FD_ATTRIBUTES | FD_FILESIZE | FD_SHOWPROGRESSUI;
	f->desc.dwFileAttributes = dir ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
	f->desc.nFileSizeHigh = (UINT32)(f->size >> 32);
	f->desc.nFileSizeLow = (UINT32)(f->size & 0xFFFFFFFF);
	(void)ConvertUtf8ToWChar(rel, f->desc.cFileName, ARRAYSIZE(f->desc.cFileName));
	clip->file_count++;
}

/* 递归添加目录内容 */
static void rmk_files_walk(RmkClipboard* clip, const char* path, const char* rel)
{
#if defined(_WIN32)
	char pattern[MAX_PATH * 2];
	sprintf_s(pattern, sizeof(pattern), "%s\\*", path);
	WIN32_FIND_DATAA fd;
	HANDLE h = FindFirstFileA(pattern, &fd);
	if (h == INVALID_HANDLE_VALUE)
		return;
	do
	{
		if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0)
			continue;
		char child[MAX_PATH * 2], childRel[MAX_PATH * 2];
		sprintf_s(child, sizeof(child), "%s\\%s", path, fd.cFileName);
		sprintf_s(childRel, sizeof(childRel), "%s\\%s", rel, fd.cFileName);
		const BOOL dir = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
		const UINT64 size = ((UINT64)fd.nFileSizeHigh << 32) | fd.nFileSizeLow;
		rmk_files_add(clip, child, childRel, dir, size);
		if (dir)
			rmk_files_walk(clip, child, childRel);
	} while (FindNextFileA(h, &fd));
	FindClose(h);
#else
	DIR* d = opendir(path);
	if (!d)
		return;
	struct dirent* e;
	while ((e = readdir(d)) != NULL)
	{
		if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0)
			continue;
		char child[4096], childRel[4096];
		snprintf(child, sizeof(child), "%s/%s", path, e->d_name);
		snprintf(childRel, sizeof(childRel), "%s\\%s", rel, e->d_name);
		struct stat st;
		if (lstat(child, &st) != 0 || S_ISLNK(st.st_mode))
			continue;
		const BOOL dir = S_ISDIR(st.st_mode);
		rmk_files_add(clip, child, childRel, dir, (UINT64)st.st_size);
		if (dir)
			rmk_files_walk(clip, child, childRel);
	}
	closedir(d);
#endif
}

/* ---------- 通道回调 ---------- */

static UINT rmk_on_monitor_ready(CliprdrClientContext* ctx, const CLIPRDR_MONITOR_READY* ready)
{
	WINPR_UNUSED(ready);
	RmkClipboard* clip = (RmkClipboard*)ctx->custom;
	CLIPRDR_GENERAL_CAPABILITY_SET general = { 0 };
	general.capabilitySetType = CB_CAPSTYPE_GENERAL;
	general.capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN;
	general.version = CB_CAPS_VERSION_2;
	general.generalFlags = CB_USE_LONG_FORMAT_NAMES | CB_STREAM_FILECLIP_ENABLED |
	                       CB_FILECLIP_NO_FILE_PATHS | CB_HUGE_FILE_SUPPORT_ENABLED;
	CLIPRDR_CAPABILITIES caps = { 0 };
	caps.cCapabilitiesSets = 1;
	caps.capabilitySets = (CLIPRDR_CAPABILITY_SET*)&general;
	UINT rc = ctx->ClientCapabilities(ctx, &caps);
	if (rc != CHANNEL_RC_OK)
		return rc;
	EnterCriticalSection(&clip->lock);
	rmk_send_format_list(clip);
	LeaveCriticalSection(&clip->lock);
	return CHANNEL_RC_OK;
}

static UINT rmk_on_server_caps(CliprdrClientContext* ctx, const CLIPRDR_CAPABILITIES* caps)
{
	RmkClipboard* clip = (RmkClipboard*)ctx->custom;
	const BYTE* p = (const BYTE*)caps->capabilitySets;
	for (UINT32 i = 0; i < caps->cCapabilitiesSets; i++)
	{
		const CLIPRDR_CAPABILITY_SET* set = (const CLIPRDR_CAPABILITY_SET*)p;
		if (set->capabilitySetType == CB_CAPSTYPE_GENERAL)
			clip->server_flags = ((const CLIPRDR_GENERAL_CAPABILITY_SET*)set)->generalFlags;
		p += set->capabilitySetLength;
	}
	return CHANNEL_RC_OK;
}

static UINT rmk_on_server_format_list(CliprdrClientContext* ctx, const CLIPRDR_FORMAT_LIST* list)
{
	RmkClipboard* clip = (RmkClipboard*)ctx->custom;
	CLIPRDR_FORMAT_LIST_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_LIST_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	UINT rc = ctx->ClientFormatListResponse(ctx, &resp);
	if (rc != CHANNEL_RC_OK)
		return rc;

	BOOL hasText = FALSE;
	clip->remote_filedesc_id = 0;
	for (UINT32 i = 0; i < list->numFormats; i++)
	{
		const CLIPRDR_FORMAT* f = &list->formats[i];
		if (f->formatId == CF_UNICODETEXT)
			hasText = TRUE;
		else if (f->formatName && strcmp(f->formatName, RMK_FILEDESC_NAME) == 0)
			clip->remote_filedesc_id = f->formatId;
	}
	/* 远程接管剪贴板，本地内容失效 */
	EnterCriticalSection(&clip->lock);
	clip->kind = RMK_LOCAL_NONE;
	LeaveCriticalSection(&clip->lock);
	if (clip->remote_filedesc_id)
		rmk_request_format(clip, clip->remote_filedesc_id);
	else if (hasText)
		rmk_request_format(clip, CF_UNICODETEXT);
	return CHANNEL_RC_OK;
}

static UINT rmk_on_server_format_list_response(CliprdrClientContext* ctx,
                                               const CLIPRDR_FORMAT_LIST_RESPONSE* resp)
{
	WINPR_UNUSED(ctx);
	WINPR_UNUSED(resp);
	return CHANNEL_RC_OK;
}

static UINT rmk_on_server_data_request(CliprdrClientContext* ctx,
                                       const CLIPRDR_FORMAT_DATA_REQUEST* req)
{
	RmkClipboard* clip = (RmkClipboard*)ctx->custom;
	EnterCriticalSection(&clip->lock);
	if (req->requestedFormatId == CF_UNICODETEXT && clip->kind == RMK_LOCAL_TEXT && clip->text)
	{
		rmk_send_data_response(clip, (const BYTE*)clip->text, (UINT32)clip->text_bytes, TRUE);
	}
	else if (req->requestedFormatId == RMK_FILEDESC_ID && clip->kind == RMK_LOCAL_FILES)
	{
		FILEDESCRIPTORW* descs = calloc(clip->file_count ? clip->file_count : 1,
		                                sizeof(FILEDESCRIPTORW));
		for (UINT32 i = 0; descs && i < clip->file_count; i++)
			descs[i] = clip->files[i].desc;
		BYTE* data = NULL;
		UINT32 len = 0;
		const UINT rc = descs ? cliprdr_serialize_file_list_ex(clip->server_flags, descs,
		                                                       clip->file_count, &data, &len)
		                      : ERROR_OUTOFMEMORY;
		rmk_send_data_response(clip, data, len, rc == CHANNEL_RC_OK);
		free(data);
		free(descs);
	}
	else
		rmk_send_data_response(clip, NULL, 0, FALSE);
	LeaveCriticalSection(&clip->lock);
	return CHANNEL_RC_OK;
}

static UINT rmk_on_server_data_response(CliprdrClientContext* ctx,
                                        const CLIPRDR_FORMAT_DATA_RESPONSE* resp)
{
	RmkClipboard* clip = (RmkClipboard*)ctx->custom;
	if (resp->common.msgFlags & CB_RESPONSE_FAIL)
		return CHANNEL_RC_OK;
	const BYTE* data = resp->requestedFormatData;
	const UINT32 len = resp->common.dataLen;
	if (clip->requested_format == CF_UNICODETEXT)
	{
		char* text = ConvertWCharNToUtf8Alloc((const WCHAR*)data, len / sizeof(WCHAR), NULL);
		if (text)
		{
			rmk_emit(clip->rdp, RMK_EV_CLIP_TEXT, 0, 0, 0, 0, text);
			free(text);
		}
	}
	else if (clip->requested_format && clip->requested_format == clip->remote_filedesc_id)
	{
		rmk_download_start(clip, data, len);
	}
	return CHANNEL_RC_OK;
}

/* 远程读取本地文件：返回大小或指定范围的数据 */
static UINT rmk_on_server_contents_request(CliprdrClientContext* ctx,
                                           const CLIPRDR_FILE_CONTENTS_REQUEST* req)
{
	RmkClipboard* clip = (RmkClipboard*)ctx->custom;
	EnterCriticalSection(&clip->lock);
	if (clip->kind != RMK_LOCAL_FILES || req->listIndex >= clip->file_count)
	{
		rmk_send_contents_response(clip, req->streamId, NULL, 0, FALSE);
		LeaveCriticalSection(&clip->lock);
		return CHANNEL_RC_OK;
	}
	RmkLocalFile* f = &clip->files[req->listIndex];
	if (req->dwFlags & FILECONTENTS_SIZE)
	{
		BYTE size[8];
		for (int i = 0; i < 8; i++)
			size[i] = (BYTE)((f->size >> (8 * i)) & 0xFF);
		rmk_send_contents_response(clip, req->streamId, size, 8, TRUE);
		LeaveCriticalSection(&clip->lock);
		return CHANNEL_RC_OK;
	}
	/* 复用上次打开的文件句柄 */
	if (!clip->serve_fp || clip->serve_index != req->listIndex)
	{
		if (clip->serve_fp)
			fclose(clip->serve_fp);
		clip->serve_fp = fopen(f->path, "rb");
		clip->serve_index = req->listIndex;
	}
	const UINT64 offset = ((UINT64)req->nPositionHigh << 32) | req->nPositionLow;
	BYTE* buf = malloc(req->cbRequested ? req->cbRequested : 1);
	size_t n = 0;
	BOOL ok = clip->serve_fp && buf && rmk_fseek(clip->serve_fp, (long long)offset, SEEK_SET) == 0;
	if (ok)
		n = fread(buf, 1, req->cbRequested, clip->serve_fp);
	rmk_send_contents_response(clip, req->streamId, buf, (UINT32)n, ok);
	free(buf);
	LeaveCriticalSection(&clip->lock);
	return CHANNEL_RC_OK;
}

/* 收到远程文件数据：写入本地并请求下一块 */
static UINT rmk_on_server_contents_response(CliprdrClientContext* ctx,
                                            const CLIPRDR_FILE_CONTENTS_RESPONSE* resp)
{
	RmkClipboard* clip = (RmkClipboard*)ctx->custom;
	if (!clip->dl_files || resp->streamId != clip->dl_stream)
		return CHANNEL_RC_OK;
	if ((resp->common.msgFlags & CB_RESPONSE_FAIL) || !clip->dl_fp)
	{
		rmk_download_reset(clip);
		return CHANNEL_RC_OK;
	}
	const UINT32 n = resp->cbRequested;
	if (n > 0)
		fwrite(resp->requestedData, 1, n, clip->dl_fp);
	clip->dl_offset += n;
	clip->dl_done += n;
	/* 每 4MB 报告一次进度 */
	if (clip->dl_done - clip->dl_last_report >= 4ull * 1024 * 1024)
	{
		clip->dl_last_report = clip->dl_done;
		rmk_emit(clip->rdp, RMK_EV_CLIP_FILES_PROGRESS, (int32_t)(clip->dl_done / 1024),
		         (int32_t)(clip->dl_total / 1024), 0, 0, NULL);
	}
	if (n == 0 || clip->dl_offset >= clip->dl_size)
	{
		fclose(clip->dl_fp);
		clip->dl_fp = NULL;
		clip->dl_index++;
	}
	rmk_download_next(clip);
	return CHANNEL_RC_OK;
}

static UINT rmk_on_lock(CliprdrClientContext* ctx, const CLIPRDR_LOCK_CLIPBOARD_DATA* l)
{
	WINPR_UNUSED(ctx);
	WINPR_UNUSED(l);
	return CHANNEL_RC_OK;
}

static UINT rmk_on_unlock(CliprdrClientContext* ctx, const CLIPRDR_UNLOCK_CLIPBOARD_DATA* u)
{
	WINPR_UNUSED(ctx);
	WINPR_UNUSED(u);
	return CHANNEL_RC_OK;
}

/* ---------- 模块接口 ---------- */

RmkClipboard* rmk_clip_new(RmkRdp* rdp)
{
	RmkClipboard* clip = calloc(1, sizeof(RmkClipboard));
	if (!clip)
		return NULL;
	clip->rdp = rdp;
	InitializeCriticalSection(&clip->lock);
	return clip;
}

void rmk_clip_free(RmkClipboard* clip)
{
	if (!clip)
		return;
	rmk_download_reset(clip);
	rmk_files_clear(clip);
	free(clip->text);
	DeleteCriticalSection(&clip->lock);
	free(clip);
}

void rmk_clip_attach(RmkClipboard* clip, CliprdrClientContext* ctx)
{
	if (!clip || !ctx)
		return;
	clip->ctx = ctx;
	ctx->custom = clip;
	ctx->MonitorReady = rmk_on_monitor_ready;
	ctx->ServerCapabilities = rmk_on_server_caps;
	ctx->ServerFormatList = rmk_on_server_format_list;
	ctx->ServerFormatListResponse = rmk_on_server_format_list_response;
	ctx->ServerFormatDataRequest = rmk_on_server_data_request;
	ctx->ServerFormatDataResponse = rmk_on_server_data_response;
	ctx->ServerFileContentsRequest = rmk_on_server_contents_request;
	ctx->ServerFileContentsResponse = rmk_on_server_contents_response;
	ctx->ServerLockClipboardData = rmk_on_lock;
	ctx->ServerUnlockClipboardData = rmk_on_unlock;
}

void rmk_clip_detach(RmkClipboard* clip)
{
	if (!clip)
		return;
	EnterCriticalSection(&clip->lock);
	if (clip->ctx)
		clip->ctx->custom = NULL;
	clip->ctx = NULL;
	LeaveCriticalSection(&clip->lock);
	rmk_download_reset(clip);
}

void rmk_clip_set_text(RmkClipboard* clip, const char* utf8)
{
	if (!clip || !utf8)
		return;
	EnterCriticalSection(&clip->lock);
	rmk_files_clear(clip);
	free(clip->text);
	size_t chars = 0;
	clip->text = ConvertUtf8ToWCharAlloc(utf8, &chars);
	clip->text_bytes = clip->text ? (chars + 1) * sizeof(WCHAR) : 0;
	clip->kind = clip->text ? RMK_LOCAL_TEXT : RMK_LOCAL_NONE;
	rmk_send_format_list(clip);
	LeaveCriticalSection(&clip->lock);
}

void rmk_clip_set_files(RmkClipboard* clip, const char* paths)
{
	if (!clip || !paths)
		return;
	EnterCriticalSection(&clip->lock);
	rmk_files_clear(clip);
	free(clip->text);
	clip->text = NULL;
	char* list = _strdup(paths);
	char* save = NULL;
	for (char* p = list ? strtok_s(list, "\n", &save) : NULL; p; p = strtok_s(NULL, "\n", &save))
	{
		struct stat st;
		if (stat(p, &st) != 0)
			continue;
		const char* base = strrchr(p, RMK_SEP);
		base = base ? base + 1 : p;
		const BOOL dir = (st.st_mode & S_IFMT) == S_IFDIR;
		rmk_files_add(clip, p, base, dir, (UINT64)st.st_size);
		if (dir)
			rmk_files_walk(clip, p, base);
	}
	free(list);
	clip->kind = clip->file_count ? RMK_LOCAL_FILES : RMK_LOCAL_NONE;
	rmk_send_format_list(clip);
	LeaveCriticalSection(&clip->lock);
}

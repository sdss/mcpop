#if !defined(MCP_SOCKETS_H)
#define MCP_SOCKETS_H

#include "data_collection.h"

int mcp_open(int port, int quiet);
void mcp_close(int s);
int read_mcp_packet(int s, struct SDSS_FRAME *inbuf, float timeout);
const char *format_mcp_packet(struct SDSS_FRAME *inbuf);

#endif

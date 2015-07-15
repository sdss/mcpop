/*****************************************************************************/
/*
 * Some MCP-packet words
 */
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "tk.h"				/* Tcl/tk support */

#include "mcp_sockets.h"

static int mcp_socket = -1;		/* socket used to connect to MCP */

static int
mcpOpenCmd(ClientData clientData,
	   Tcl_Interp *interp,
	   int ac,
	   char **av)
{
   if(mcp_socket > 0) {
      interp->result = "The MCP port seems to already be open";
      return TCL_ERROR;
   }

   char const *cmd = av[0];

   av++; ac--;

   int port = -1;			/* Port to connect to */
   if (ac == 1) {
      int err = Tcl_GetInt(interp, av[0], &port);
      if (err != TCL_OK) {
	 return err;
      }
      av++; ac--; 
   }

   if (ac > 0) {
      sprintf(interp->result, "Usage: %s [port]", cmd) ;
      return TCL_ERROR;
   }

   if((mcp_socket = mcp_open(port, 1)) < 0) {
      sprintf(interp->result, "Opening MCP port %d", port);
      return TCL_ERROR;
   }

   return TCL_OK;
}

static int
mcpCloseCmd(ClientData clientData,
	    Tcl_Interp *interp,
	    int ac,
	    char **av)
{
   if (ac != 1) {
      sprintf(interp->result, "Usage: %s", av[0]) ;
      return TCL_ERROR;
   }

   if(mcp_socket <= 0) {
      interp->result = "The MCP port doesn't seem to be open";
      return TCL_ERROR;
   }

   mcp_close(mcp_socket);
   mcp_socket = -1;

   return TCL_OK;
}

static int
mcpReadPacketCmd(ClientData clientData,
	      Tcl_Interp *interp,
	      int ac,
	      char **av)
{
   int nocheck = 0;			/* Don't check UDP packet length */
   double timeout = 0.5;		/* Timeout waiting for a packet */

   if(mcp_socket <= 0) {
      Tcl_AppendResult(interp, "The MCP port doesn't seem to be open",
		       (char *)NULL);
      return TCL_ERROR;
   }

   char const *cmd = av[0];

   av++; ac--;
   while (ac > 0) {
      if (strcmp(av[0], "-nocheck") == 0) {
	 nocheck = 1;
      } else if (strcmp(av[0], "-timeout") == 0) {
	 if (ac < 2) {
	    sprintf(interp->result, "Please specify a value for %s %s", cmd, av[0]);
	    return TCL_ERROR;
	 }
	 timeout = atof(av[1]);
	 av++; ac--;
      } else {
	 sprintf(interp->result, "Usage: %s [-nocheck] [-timeout dt]", cmd);
      }

      av++; ac--;
   }

   if (ac != 0) {
      sprintf(interp->result, "Usage: %s [-nocheck] [-timeout dt]", cmd);
      return TCL_ERROR;
   }
      
   struct SDSS_FRAME inbuf;
   int nread;				/* number of bytes read */
   
   if((nread = read_mcp_packet(mcp_socket, &inbuf, timeout)) == sizeof(inbuf) || (nread > 0 && nocheck)) {
      const char *packet = format_mcp_packet(&inbuf);
      Tcl_SetResult(interp, (char *)packet, TCL_STATIC);
   } else {
      if(nread < 0) {
	 if(errno == 0) {		/* just a timeout */
	    return TCL_OK;
	 }

	 sprintf(interp->result, "mcpReadPacket failed: %s", strerror(errno));
      } else {
	 sprintf(interp->result, "mcpReadPacket: read_mcp_packet returned %d", nread);
      }
      
      return TCL_ERROR;
   }

   return TCL_OK;
}

/*****************************************************************************/

static int
mcpGetFieldsCmd(ClientData clientData,
		Tcl_Interp *interp,
		int ac,
		char **av)
{
   if (ac != 1) {
      sprintf(interp->result, "Usage: %s", av[0]) ;
      return TCL_ERROR;
   }

   struct SDSS_FRAME dummy;		/* stucture to format */

   memset(&dummy, '\0', sizeof(dummy));

   const char *packet = format_mcp_packet(&dummy);
   Tcl_SetResult(interp, (char *)packet, TCL_STATIC);

   return TCL_OK;
}

/*****************************************************************************/

static int
mcpIsOpenCmd(ClientData clientData,
	     Tcl_Interp *interp,
	     int ac,
	     char **av)
{
   if (ac != 1) {
      sprintf(interp->result, "Usage: %s", av[0]) ;
      return TCL_ERROR;
   }

   sprintf(interp->result, "%d", (mcp_socket >= 0) ? 1 : 0);

   return TCL_OK;
}

/*****************************************************************************/
/*
 * Declare my new tcl verbs to tcl
 */
void
mcpTclVerbsDeclare(Tcl_Interp *interp)
{
   Tcl_CreateCommand(interp, "mcpOpen", mcpOpenCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
   Tcl_CreateCommand(interp, "mcpClose", mcpCloseCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
   Tcl_CreateCommand(interp, "mcpReadPacket", mcpReadPacketCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
   Tcl_CreateCommand(interp, "mcpGetFields", mcpGetFieldsCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
   Tcl_CreateCommand(interp, "mcpIsOpen", mcpIsOpenCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
}

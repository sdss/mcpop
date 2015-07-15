#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

#include "tk.h"			/* Tcl/tk support */
#include "dp.h"			/* Tcl-DP support */

/*****************************************************************************/
/*
 * Source a file given by an environment variable
 */

static int
source(Tcl_Interp *interp, char *file)
{
   char cmd[200];
   char *script = getenv(file);
   
   if(script != NULL) {
      if(*script != '\0') {
	 sprintf(cmd, "source %s",script);
	 printf("Executing commands in %s: ",script);
	 Tcl_Eval(interp, cmd);
	 putchar('\n');
	 if(*interp->result != '\0') {
	    printf("--> %s\n", interp->result);
	 }
	 fflush(stdout);
      }
      return(0);
   } else {
      return(-1);
   }
}

/*****************************************************************************/

int
ClockCmd(ClientData clientData,
	 Tcl_Interp *interp,
	 int ac,
	 char **av
   )
{
   if (ac > 1) {
      sprintf(interp->result, "%s takes no arguments", av[0]);
      return TCL_ERROR;
   }

   sprintf(interp->result, "%ld", time(NULL));
   return TCL_OK;
}

/*****************************************************************************/

int
get_fd(Tcl_Interp *interp, char *tclFile, int write, fd_set *fds, int *nfd)
{
   FD_ZERO(fds);
   
   if (*tclFile == '\0') {
      return 0;
   }

   FILE *file;
   if (Tcl_GetOpenFile(interp, tclFile, write, 0, &file) == TCL_ERROR) {
      return -1;
   }

   int fd = fileno(file);
   FD_SET(fd, fds);

   if (fd > *nfd) {
      *nfd = fd;
   }

   return 0;
}

int
MySelectCmd(ClientData clientData,
	 Tcl_Interp *interp,
	 int ac,
	 char **av
   )
{
   if (ac != 5) {
      sprintf(interp->result, "Usage: %s r_fd w_fd x_fd timedelay", av[0]) ;
      return TCL_ERROR;
   }

   int fd_max;				/* largest file descriptor in use  */
   fd_set rfd;
   if (get_fd(interp, av[1], 0, &rfd, &fd_max) < 0) {
      return TCL_ERROR;
   }

   fd_set wfd;
   if (get_fd(interp, av[2], 1, &wfd, &fd_max) < 0) {
      return TCL_ERROR;
   }

   fd_set xfd;
   if (get_fd(interp, av[2], 0, &xfd, &fd_max) < 0) {
      return TCL_ERROR;
   }

   double dt = 0;
   int err = Tcl_GetDouble(interp, av[4], &dt);
   if (err != TCL_OK) {
      return err;
   }

   struct timeval timeout;
   /* Set time limit. */
   timeout.tv_sec = (int)dt;
   timeout.tv_usec = 1e6*(dt - timeout.tv_sec);

   int nfd = select(fd_max + 1, &rfd, &wfd, NULL, &timeout);
   if (nfd == 0) {
      interp->result = "";
   } else {
      interp->result = "OK";
   }

   return TCL_OK;
}

/*****************************************************************************/

int
UtClockCmd(ClientData clientData,
	 Tcl_Interp *interp,
	 int ac,
	 char **av
   )
{
   if (ac > 2) {
      sprintf(interp->result, "%s time", av[0]);
      return TCL_ERROR;
   }

   int clock = 0;
   int err = Tcl_GetInt(interp, av[1], &clock);
   if (err != TCL_OK) {
      return err;
   }
   time_t rawtime = clock;

   strftime(interp->result, 200, "%Y-%m-%d %H:%M:%SZ", gmtime(&rawtime));

   return TCL_OK;
}

/*****************************************************************************/
#include <pwd.h>
int
WhoAmICmd(ClientData clientData,
	 Tcl_Interp *interp,
	 int ac,
	 char **av
   )
{
   if (ac > 1) {
      sprintf(interp->result, "%s", av[0]);
      return TCL_ERROR;
   }

   struct passwd *pwd = getpwuid(geteuid());
   interp->result = (pwd == NULL) ? "???" : pwd->pw_name;

   return TCL_OK;
}

/*****************************************************************************/

int Tk_AppInit(Tcl_Interp *interp)
{
   Tk_Window main_window = Tk_MainWindow(interp);
   
   if (Tcl_Init(interp) == TCL_ERROR ||
       (main_window && Tk_Init(interp)) == TCL_ERROR ||
       Tdp_Init(interp) == TCL_ERROR) {
      return TCL_ERROR;
   }
/*
 * Define procs that we need
 */
   Tcl_CreateCommand(interp, "getclock", ClockCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
   Tcl_CreateCommand(interp, "mySelect", MySelectCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
   Tcl_CreateCommand(interp, "utclock", UtClockCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
   Tcl_CreateCommand(interp, "whoami", WhoAmICmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);

   void mcpTclVerbsDeclare(Tcl_Interp *interp);
   mcpTclVerbsDeclare(interp);
/*
 * Execute any Tcl startup scripts.
 */
   source(interp, "PCPOP_STARTUP");
   source(interp, "MCPOP_USER");

   return TCL_OK;
}

/*****************************************************************************/

int
main(int ac, char *av[])
{
   if (0) {
      Tcl_Interp *interp = Tcl_CreateInterp();
      /*
       * Tcl-DP must be initialized before Tk's main event loop is entered,
       * and it needs an interp for error messages
       */
      if (Tdp_Init (interp) == TCL_ERROR) {
	 fprintf (stderr,"%%%%: Tdp_Init failed\n");
	 fprintf (stderr,"  %s\n", interp->result);
      }
      Tcl_DeleteInterp(interp);
   }

   Tk_Main(ac, av, Tk_AppInit);
   return 0;
}

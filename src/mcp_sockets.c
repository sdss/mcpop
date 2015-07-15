#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <errno.h>
#include <string.h>
#include <assert.h>
#include "mcp_sockets.h"

#define SLOAN_BCAST_PORT 0x6804

#if defined(SDSS_LITTLE_ENDIAN)
   static void flip_bits_in_bytes(void *vptr, int n);
   static void swab2(void *, int n);
   static void swab4(void *, int n);
#  if 0
      static void swab8(void *, int n);
#  endif
#endif

int
mcp_open(int port,			/* the port to use; -1 => default */
	 int quiet)			/* don't print errors? */
{
   struct sockaddr_in from_addr;
#if defined(SO_REUSEADDR) || defined(SO_REUSEPORT)
   const int one = 1;
#endif
   int s;

   if(port < 0) {
      port = SLOAN_BCAST_PORT;
   }
   /*
    * Create the socket we receive on
    */
   s=socket(AF_INET,SOCK_DGRAM,0);
   if (s < 0) {
      if(!quiet) {
	 perror("Couldn't get MCP socket");
      }
      return(-1);
   }

#if defined(SO_REUSEPORT)
   if(setsockopt(s,SOL_SOCKET,SO_REUSEPORT,(char *)&one,sizeof(one)) < 0) {
      if(!quiet) {
	 perror("Setting REUSEPORT on MCP socket");
      }
      close(s);
      return(-1);
   }
#elif defined(SO_REUSEADDR)
   if(setsockopt(s,SOL_SOCKET,SO_REUSEADDR,(char *)&one,sizeof(one)) < 0) {
      if(!quiet) {
	 perror("Setting REUSEADDR on MCP socket");
      }
      close(s);
      return(-1);
   }
#endif
  /*
   * Bind the socket to the port we want to listen to
   */
   memset((char *)&from_addr,0,sizeof(from_addr));
   from_addr.sin_family = AF_INET;
   from_addr.sin_addr.s_addr = htonl(INADDR_ANY);
   /*
    * Set the internet service port we're connecting
    */
   from_addr.sin_port = htons(port);

   if (bind(s,(struct sockaddr *)&from_addr, sizeof(from_addr)) < 0){
      if(!quiet) {
	 perror("Can't bind local address");
      }
      close(s);
      return(-1);
   }
   
   memset((char *)&from_addr,0,sizeof(from_addr));

   return(s);
}

void
mcp_close(int s)
{
   close(s);
}

int
read_mcp_packet(int s,
		struct SDSS_FRAME *inbuf,
		float timeout)
{
   struct sockaddr_in from_addr;
   unsigned int lenfrom = sizeof(from_addr);
   int nread;
   fd_set read_fds;			/* information for select() */
   struct timeval timeout_s;		/* timeout for select */
/*
 * Is there anything to read?
 */
   timeout_s.tv_sec = (int)timeout;
   timeout_s.tv_usec = 1e6*(timeout - timeout_s.tv_sec);
   FD_ZERO(&read_fds);
   FD_SET(s, &read_fds);
   if(select(s + 1, &read_fds, NULL, NULL, &timeout_s) <= 0) {
      return(-1);
   }
/*
 * Make sure that we read the latest packet
 */
   timeout_s.tv_sec = timeout_s.tv_usec = 0;
   while(1) {
      nread = recvfrom(s, inbuf, sizeof(struct SDSS_FRAME),
		       0, (struct sockaddr *)&from_addr, &lenfrom);

      FD_ZERO(&read_fds);
      FD_SET(s, &read_fds);
      if(select(s + 1, &read_fds, NULL, NULL, &timeout_s) <= 0) {
	 break;
      }
   }

   return(nread);
}

/*****************************************************************************/
/*
 * Return a formatted string giving the contents of an SDSS_FRAME
 */
#define AXIS_NFIELD 5			/* number of fields in inbuf->axis */
#define CW_NFIELD 2			/* number of fields in inbuf->weight */
#define NFIELD AXIS_NFIELD		/* max of the above */

const char *
format_mcp_packet(struct SDSS_FRAME *inbuf)
{
   const char *axis_names[] = {		/* names of the axes */
      "az", "alt", "rot"
   };
   const char *axis_field_names[AXIS_NFIELD] = { /* names of fields in axis[]*/
      "pos1", "pos2", "vel", "accel", "error"
   };
   const char *cw_field_names[CW_NFIELD] = { /* names of fields in weight[]*/
      "status", "pos"
   };
   static char buff[19000];		/* returned buffer */
   char *bptr = buff;
   int i, j;
   unsigned int val[NFIELD];		/* values from inbuf->axis[] */
/*
 * first axes and axis_state
 */
   for(i = 0; i < 3; i++) {
#if defined(SDSS_LITTLE_ENDIAN)
      swab4(&inbuf->axis_state[i], sizeof(inbuf->axis_state[0]));
#endif
      sprintf(bptr, "%s%s %d\n", axis_names[i],"state",inbuf->axis_state[i]);
      bptr += strlen(bptr);

#if defined(SDSS_LITTLE_ENDIAN)
      swab2(&inbuf->axis[i], sizeof(inbuf->axis[0]));
#endif

      j = 0;
      val[j++] = (inbuf->axis[i].actual_position_hi << 16) |
			 *(unsigned short *)&inbuf->axis[i].actual_position_lo;
      val[j++] = (inbuf->axis[i].actual_position2_hi << 16) |
			*(unsigned short *)&inbuf->axis[i].actual_position2_lo;
      val[j++] = (inbuf->axis[i].velocity_hi << 16) |
				*(unsigned short *)&inbuf->axis[i].velocity_lo;
      val[j++] = (inbuf->axis[i].acceleration_hi << 16) |
			    *(unsigned short *)&inbuf->axis[i].acceleration_lo;
      val[j++] = inbuf->axis[i].error;
      assert(j == AXIS_NFIELD && j <= NFIELD);

      for(j = 0; j < AXIS_NFIELD; j++) {
	 sprintf(bptr, "%s%s:val %d\n", axis_names[i], axis_field_names[j], val[j]);
	 bptr += strlen(bptr);
      }
   }
/*
 * then the counterweights
 */
   for(i = 0;i < 4; i++) {
#if defined(SDSS_LITTLE_ENDIAN)
      swab2(&inbuf->weight[i], sizeof(inbuf->weight[i]));
#endif
      
      j = 0;
      val[j++] = inbuf->weight[i].status;
      val[j++] = inbuf->weight[i].pos;
      assert(j == CW_NFIELD && j <= NFIELD);

      for(j = 0; j < CW_NFIELD; j++) {
	 sprintf(bptr, "cw%d%s:val %d\n", i + 1, cw_field_names[j], val[j]);
	 bptr += strlen(bptr);
      }
   }
/*
 * there's one odd-man-out, the string inbuf->ascii
 */
   sprintf(bptr, "state_ascii {%s}\n", inbuf->ascii);
   bptr += strlen(bptr);
/*
 * The printout.c file is generated from data_collection.h by parse.tcl
 */
#include "printout.c"

   assert(bptr - buff < sizeof(buff) - 1);
   return(buff);
}

#if defined(SDSS_LITTLE_ENDIAN)
/*
 * utility functions to swap bits/bytes
 */
static void
flip_bits_in_bytes(void *vptr, int n)
{
   static const unsigned char flip_bits[256] = {
      0000, 0200, 0100, 0300, 0040, 0240, 0140, 0340, 
      0020, 0220, 0120, 0320, 0060, 0260, 0160, 0360, 
      0010, 0210, 0110, 0310, 0050, 0250, 0150, 0350, 
      0030, 0230, 0130, 0330, 0070, 0270, 0170, 0370, 
      0004, 0204, 0104, 0304, 0044, 0244, 0144, 0344, 
      0024, 0224, 0124, 0324, 0064, 0264, 0164, 0364, 
      0014, 0214, 0114, 0314, 0054, 0254, 0154, 0354, 
      0034, 0234, 0134, 0334, 0074, 0274, 0174, 0374, 
      0002, 0202, 0102, 0302, 0042, 0242, 0142, 0342, 
      0022, 0222, 0122, 0322, 0062, 0262, 0162, 0362, 
      0012, 0212, 0112, 0312, 0052, 0252, 0152, 0352, 
      0032, 0232, 0132, 0332, 0072, 0272, 0172, 0372, 
      0006, 0206, 0106, 0306, 0046, 0246, 0146, 0346, 
      0026, 0226, 0126, 0326, 0066, 0266, 0166, 0366, 
      0016, 0216, 0116, 0316, 0056, 0256, 0156, 0356, 
      0036, 0236, 0136, 0336, 0076, 0276, 0176, 0376, 
      0001, 0201, 0101, 0301, 0041, 0241, 0141, 0341, 
      0021, 0221, 0121, 0321, 0061, 0261, 0161, 0361, 
      0011, 0211, 0111, 0311, 0051, 0251, 0151, 0351, 
      0031, 0231, 0131, 0331, 0071, 0271, 0171, 0371, 
      0005, 0205, 0105, 0305, 0045, 0245, 0145, 0345, 
      0025, 0225, 0125, 0325, 0065, 0265, 0165, 0365, 
      0015, 0215, 0115, 0315, 0055, 0255, 0155, 0355, 
      0035, 0235, 0135, 0335, 0075, 0275, 0175, 0375, 
      0003, 0203, 0103, 0303, 0043, 0243, 0143, 0343, 
      0023, 0223, 0123, 0323, 0063, 0263, 0163, 0363, 
      0013, 0213, 0113, 0313, 0053, 0253, 0153, 0353, 
      0033, 0233, 0133, 0333, 0073, 0273, 0173, 0373, 
      0007, 0207, 0107, 0307, 0047, 0247, 0147, 0347, 
      0027, 0227, 0127, 0327, 0067, 0267, 0167, 0367, 
      0017, 0217, 0117, 0317, 0057, 0257, 0157, 0357, 
      0037, 0237, 0137, 0337, 0077, 0277, 0177, 0377, 
   };
   int i;
   unsigned char *ptr = vptr;

   for(i = 0; i < n; i++) {
      ptr[i] = flip_bits[(int)ptr[i]];
   }
}

/*
 * swap bytes
 */
static void
swab2(void *vptr,			/* starting address of data */
      int n)				/* number of _bytes_ to swap */
{
   int i;
   unsigned char *ptr, tmp;

   for(i = 0, ptr = vptr; i < n; i += 2, ptr += 2) {
      tmp = ptr[0];
      ptr[0] = ptr[1];
      ptr[1] = tmp;
   }
}

static void
swab4(void *vptr,			/* starting address of data */
      int n)				/* number of _bytes_ to swap */      
{
   int i;
   unsigned char *ptr, tmp;

   for(i = 0, ptr = vptr; i < n; i += 4, ptr += 4) {
      tmp = ptr[0];
      ptr[0] = ptr[3];
      ptr[3] = tmp;
      tmp = ptr[1];
      ptr[1] = ptr[2];
      ptr[2] = tmp;
   }
}

#if 0
static void
swab8(void *vptr,			/* starting address of data */
      int n)				/* number of _bytes_ to swap */
{
   int i;
   unsigned char *ptr, tmp;

   for(i = 0, ptr = vptr; i < n; i += 8, ptr += 8) {
      tmp = ptr[0];
      ptr[0] = ptr[7];
      ptr[7] = tmp;
      tmp = ptr[1];
      ptr[1] = ptr[6];
      ptr[6] = tmp;
      tmp = ptr[2];
      ptr[2] = ptr[5];
      ptr[5] = tmp;
      tmp = ptr[3];
      ptr[3] = ptr[4];
      ptr[4] = tmp;
   }
}
#endif
#endif

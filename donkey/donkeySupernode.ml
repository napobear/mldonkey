(* Copyright 2001, 2002 Francois *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

(*
Supernode behavior for mldonkey...

A supernode acts as a server, but:
- it doesnot index its clients (since only mldonkey clients)
- it browses and index overnet+edonkey clients, without staying 
    connected. It specialized in clients whose MD4 are closed to
    its MD4.
- mldonkey clients connect to 16 supernodes (the space of MD4 is
    partitioned into 16 regions). 16 should be configurable.
*)

open Md4
open Options

open CommonResult
open CommonTypes
open CommonOptions
open CommonRoom
open CommonShared
open CommonGlobals
open CommonFile
open CommonClient
open CommonComplexOptions
open GuiProto
open BasicSocket
open TcpBufferedSocket
open DonkeyMftp
open DonkeyProtoCom
open DonkeyTypes  
open DonkeyOptions
open DonkeyComplexOptions
open DonkeyGlobals

type protocol =

(* Basic protocol between mldonkey clients *)
    Connect of 
          (Ip.t * int * Md4.t)      (* client identification *)
        * int                       (* protocol version *)
        * int                       (* supernodes needed (bitfield) *)
        * int                       (* supernode activity *)
        * int * int * int * int * int (* which NetworkInfo we need *)
  | NetworkInfo of 
          bool                      (* accept as client *)
	* (Ip.t * int * Md4.t) list (* browsable peers with MD4 for supernode *)
	* (Ip.t * int) list         (* browsable peers for supernode *)
	* (Ip.t * int) list         (* servers *)
	* (Ip.t * int) list         (* overnet peers *)
        * (Ip.t * int * Md4.t) list (* supernodes *)

(* Localization of downloaded files *)
  | RegisterDownloads of 
          (Md4.t * int32) list      (* hash and size of downloads *)
  | KnownSources of 
          Md4.t                     (* Md4 of file *)
        * (Ip.t * int) list         (* sources *)

(* Search of interesting files *)
  | Search of
          int * int                 (* search id and offset *)
        * CommonTypes.query
  | SearchReply of
          int                       (* search id *)
        * tagged_file list


type browsed_node = {
    node_ip : Ip.t;
    node_port : int;
    mutable node_files : tagged_file list;
    mutable node_md4 : Md4.t;
    mutable node_last_browse : float;
  }

let supernode_browse_handler node msg sock =
  let module M = DonkeyProtoClient in
  match msg with

  | M.ViewFilesReplyReq t ->
      Printf.printf "****************************************";
      print_newline ();
      Printf.printf "       BROWSE FILES REPLY         ";
      print_newline ();
      let module Q = M.ViewFilesReply in

      begin
        try
	  node.node_files <- t;
          let list = ref [] in
          List.iter (fun f ->
              match result_of_file f.f_md4 f.f_tags with
                None -> ()
              | Some r ->
(*
                  let r = DonkeyIndexer.index_result_no_filter r in
*)
		  ()
          ) t;
        with e ->
            Printf.printf "Exception in ViewFilesReply %s"
              (Printexc2.to_string e); print_newline ();
      end;
      node.node_last_browse <- last_time ();
      close sock "browsed"

  | M.ConnectReplyReq t ->      
      printf_string "******* [BROWSE CCONN OK] ********"; 
      let module CR = M.ConnectReply in      
      node.node_md4 <- t.CR.md4;
      
  | _ -> (* Don't care about other messages *)
      ()

let supernode_browse_client node =
  try
    let sock = TcpBufferedSocket.connect "supernode browse client" 
      (Ip.to_inet_addr node.node_ip)  node.node_port (fun _ _ -> ()) in
  TcpBufferedSocket.set_read_controler sock download_control;
  TcpBufferedSocket.set_write_controler sock upload_control;
  set_rtimeout sock !!client_timeout;
  set_handler sock (BASIC_EVENT RTIMEOUT) (fun s ->
      printf_string "[BR?]";
      close s "timeout"
  );
  set_reader sock (DonkeyProtoCom.cut_messages DonkeyProtoClient.parse
		     (supernode_browse_handler node));
  let server_ip, server_port =         
    try
      let s = DonkeyGlobals.last_connected_server () in
      s.server_ip, s.server_port
    with _ -> Ip.localhost, 4665
  in
  direct_client_send sock (
   let module M = DonkeyProtoClient in
   let module C = M.Connect in
   M.ConnectReq {
    C.md4 = !!client_md4;
    C.ip = client_ip None;
    C.port = !client_port;
    C.tags = !client_tags;
    C.version = 16;
    C.ip_server = server_ip;
    C.port_server = server_port;
    });
  direct_client_send sock (
    let module M = DonkeyProtoClient in
    let module C = M.ViewFiles in
    M.ViewFilesReq C.t)
    with _ -> ()


(*  
let client_connection_handler t event =
  printf_string "[REMOTE CONN]";
  match event with
    TcpServerSocket.CONNECTION (s, Unix.ADDR_INET (from_ip, from_port)) ->
      
      if can_open_connection () then
        begin
          try
            let c = ref None in
            let sock = 
              TcpBufferedSocket.create "donkey client connection" s 
                (client_handler2 c) 
(*client_msg_to_string*)
            in
            init_connection sock;
            
            (try
                set_reader sock 
                  (DonkeyProtoCom.client_handler2 c read_first_message
                    (client_to_client []));
              
              with e -> Printf.printf "Exception %s in init_connection"
                    (Printexc2.to_string e);
                  print_newline ());
          with e ->
              Printf.printf "Exception %s in client_connection_handler"
                (Printexc2.to_string e);
              print_newline ();
              Unix.close s
        end      
      else begin
          Unix.close s
        end;
  | _ -> 
      ()      
*)

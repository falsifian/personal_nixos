{runCommand}: job:

(
  if job ? jobDrv then
    job.jobDrv
  else
    (
      runCommand job.name {inherit (job) job;}
        "ensureDir $out/etc/event.d; echo \"$job\" > $out/etc/event.d/$name"
    )
)

//

{
  # Allow jobs to declare extra packages that should be added to the
  # system path.
  extraPath = if job ? extraPath then job.extraPath else [];

  # Allow jobs to declare extra files that should be added to /etc.
  extraEtc = if job ? extraEtc then job.extraEtc else [];

  # Allow jobs to declare user accounts that should be created.
  users = if job ? users then job.users else [];
}

package clinicaltrials.domain;

import java.util.Collection;
import java.util.Comparator;
import java.util.HashSet;
import java.util.TreeSet;
import clinicaltrials.domain.Participant;
import clinicaltrials.domain.Consent;

public class Study extends DomainObject
{
	/**
	 * The event calendarEventPoint comparator.
	 */
	private static final Comparator<StudyEvent> eventComparator = createEventComparator();

    /**
     * The Study name.
     */
    private String name;

    /**
     * The Study status (Active or Inactive).
     */
    private String activityStatus;

    /**
     * The user coordinating this Study.
     * <p>
     * This property exercises a required independent single-valued reference.
     * </p>
     */
    private User coordinator;

    /**
     * Collection of study events associated with the Study.
     * <p>
     * This property exercises a dependent multi-valued reference.
     * The return type is unparameterized in order to exercise the collection suffix
     * type inference heuristic.
     * </p>
     */
    private Collection studyEventCollection = new TreeSet<StudyEvent>(eventComparator);

    /**
     * Collection of participants enrolled in the Study.
     * <p>
     * This property exercises an independent multi-valued reference.
     * </p>
     */
    private Collection<Participant> enrollment = new HashSet<Participant>();

    /**
     * Collection of consents in the Study.
     * <p>
     * This property exercises a dependent collection reference without an owner attribute or secondary key.
     * </p>
     */
    private Collection<Consent> consentCollection = new HashSet<Consent>();

    public Study()
    {
    }

    /**
     * @return the Study name
     */
    public String getName()
    {
        return name;
    }

    /**
     * @param name the name to set
     */
    public void setName(String name)
    {
        this.name = name;
    }

    /**
     * @return the Study status (Active or Inactive)
     */
    public String getActivityStatus()
    {
        return activityStatus;
    }

    /**
     * @param activityStatus the status to set
     */
    public void setActivityStatus(String activityStatus)
    {
        this.activityStatus = activityStatus;
    }

    /**
     * @return the study events
     */
    public Collection getStudyEventCollection()
    {
        return studyEventCollection;
    }

    /**
     * @param studyEventCollection the StudyEvent collection to set
     */
    public void setStudyEventCollection(Collection<StudyEvent> studyEventCollection)
    {
        this.studyEventCollection = studyEventCollection;
    }

    /**
     * @return the study events
     */
    public Collection getConsentCollection()
    {
        return consentCollection;
    }

    /**
     * @param consentCollection the Consent collection to set
     */
    public void setConsentCollection(Collection<Consent> consentCollection)
    {
        this.consentCollection = consentCollection;
    }

    /**
     * @return the coordinator for this study.
     */
    public User getCoordinator()
    {
        return coordinator;
    }

    /**
     * @param the coordinator for this study.
     */
    public void setCoordinator(User coordinator)
    {
        this.coordinator = coordinator;
    }

    /**
     * @return the collection of participants for this study.
     */
    public Collection<Participant> getEnrollment()
    {
        return enrollment;
    }

    /**
     * @param the collection of participants for this study.
     */
    public void setEnrollment(Collection<Participant> enrollment)
    {
        this.enrollment = enrollment;
    }

    private static Comparator<StudyEvent> createEventComparator()
    {
    	return new Comparator<StudyEvent>() {
			public int compare(StudyEvent e1, StudyEvent e2) {
				Double p1 = e1.getCalendarEventPoint();
				Double p2 = e2.getCalendarEventPoint();
				if (p1 == null) {
					return p2 == null ? 0 : -1;
				} else {
					return p2 == null ? 1 : p1.compareTo(p2);
				}
			}
		};
    }
}
